import Foundation
import Combine

// MARK: - Notes Sort Options

enum NotesSortOption: String, CaseIterable {
    case dateCreated = "Date Created"
    case dateModified = "Recently Modified"
    case title = "Title"
    case pinned = "Pinned First"
    
    func sort(_ notes: [Note]) -> [Note] {
        switch self {
        case .dateCreated:
            return notes.sorted { $0.dateCreated > $1.dateCreated }
        case .dateModified:
            return notes.sorted { $0.dateModified > $1.dateModified }
        case .title:
            return notes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .pinned:
            return notes.sorted { (n1, n2) in
                if n1.isPinned != n2.isPinned {
                    return n1.isPinned
                }
                return n1.dateModified > n2.dateModified
            }
        }
    }
}

// MARK: - Notes Filter Options

enum NotesFilterOption: String, CaseIterable {
    case all = "All Notes"
    case pinned = "Pinned"
    case withDocument = "Linked to Document"
    case standalone = "Standalone"
    
    func filter(_ notes: [Note]) -> [Note] {
        switch self {
        case .all:
            return notes
        case .pinned:
            return notes.filter { $0.isPinned }
        case .withDocument:
            return notes.filter { $0.documentId != nil }
        case .standalone:
            return notes.filter { $0.documentId == nil }
        }
    }
}

// MARK: - Notes View Model

@MainActor
final class NotesViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var notes: [Note] = []
    @Published private(set) var filteredNotes: [Note] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    // MARK: - UI State
    
    @Published var searchQuery: String = ""
    @Published var selectedSort: NotesSortOption = .dateModified
    @Published var selectedFilter: NotesFilterOption = .all
    @Published var selectedNote: Note?
    @Published var currentDocumentId: UUID?
    
    // MARK: - Dependencies
    
    private let repo: NotesRepository
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(repo: NotesRepository) {
        self.repo = repo
        setupObservers()
    }
    
    private func setupObservers() {
        // Auto-update filtered notes
        Publishers.CombineLatest4(
            $notes,
            $searchQuery,
            $selectedSort,
            $selectedFilter
        )
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] notes, query, sort, filter in
            self?.applyFiltersAndSort(notes: notes, query: query, sort: sort, filter: filter)
        }
        .store(in: &cancellables)
        
        // Listen for current document changes
        $currentDocumentId
            .sink { [weak self] documentId in
                if let documentId = documentId {
                    Task { await self?.loadForDocument(documentId) }
                } else {
                    Task { await self?.loadAll() }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Loading
    
    func loadAll() async {
        isLoading = true
        error = nil
        
        do {
            notes = try await repo.all()
        } catch {
            self.error = error
            notes = []
            Log.error("Failed to load notes: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func loadForDocument(_ documentId: UUID) async {
        isLoading = true
        error = nil
        
        do {
            notes = try await repo.forDocument(documentId: documentId)
        } catch {
            self.error = error
            notes = []
            Log.error("Failed to load notes for document: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    // MARK: - Filtering & Sorting
    
    private func applyFiltersAndSort(
        notes: [Note],
        query: String,
        sort: NotesSortOption,
        filter: NotesFilterOption
    ) {
        var result = notes
        
        // Apply filter
        result = filter.filter(result)
        
        // Apply search
        if !query.isEmpty {
            let lowercased = query.lowercased()
            result = result.filter { note in
                note.title.lowercased().contains(lowercased) ||
                note.content.lowercased().contains(lowercased) ||
                note.tags.contains { $0.lowercased().contains(lowercased) }
            }
        }
        
        // Apply sort
        result = sort.sort(result)
        
        self.filteredNotes = result
    }
    
    // MARK: - CRUD Operations
    
    func createNote(title: String, content: String = "", documentId: UUID? = nil) async {
        let note = Note(
            documentId: documentId ?? currentDocumentId,
            title: title,
            content: content
        )
        
        do {
            try await repo.save(note)
            await reload()
            selectedNote = note
        } catch {
            self.error = error
            Log.error("Failed to create note: \(error.localizedDescription)")
        }
    }
    
    func updateNote(_ note: Note) async {
        var updatedNote = note
        updatedNote.dateModified = Date()
        
        do {
            try await repo.update(updatedNote)
            await reload()
            
            // Update selected note if it's the same
            if selectedNote?.id == note.id {
                selectedNote = updatedNote
            }
        } catch {
            self.error = error
            Log.error("Failed to update note: \(error.localizedDescription)")
        }
    }
    
    func deleteNote(id: UUID) async {
        do {
            try await repo.delete(id: id)
            await reload()
            
            // Clear selection if deleted
            if selectedNote?.id == id {
                selectedNote = nil
            }
        } catch {
            self.error = error
            Log.error("Failed to delete note: \(error.localizedDescription)")
        }
    }
    
    func togglePin(noteId: UUID) async {
        guard let note = notes.first(where: { $0.id == noteId }) else { return }
        
        var updatedNote = note
        updatedNote.isPinned.toggle()
        updatedNote.dateModified = Date()
        
        await updateNote(updatedNote)
    }
    
    func updateContent(noteId: UUID, content: String) async {
        guard let note = notes.first(where: { $0.id == noteId }) else { return }
        
        var updatedNote = note
        updatedNote.content = content
        
        await updateNote(updatedNote)
    }
    
    func updateTags(noteId: UUID, tags: [String]) async {
        guard let note = notes.first(where: { $0.id == noteId }) else { return }
        
        var updatedNote = note
        updatedNote.tags = tags
        
        await updateNote(updatedNote)
    }
    
    // MARK: - Helpers
    
    private func reload() async {
        if let documentId = currentDocumentId {
            await loadForDocument(documentId)
        } else {
            await loadAll()
        }
    }
    
    // MARK: - Statistics
    
    var totalNotes: Int {
        notes.count
    }
    
    var pinnedNotes: [Note] {
        notes.filter { $0.isPinned }
    }
    
    var recentNotes: [Note] {
        notes
            .sorted { $0.dateModified > $1.dateModified }
            .prefix(5)
            .map { $0 }
    }
    
    var notesForCurrentDocument: [Note] {
        guard let documentId = currentDocumentId else { return [] }
        return notes.filter { $0.documentId == documentId }
    }
}
