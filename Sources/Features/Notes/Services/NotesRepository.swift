import Foundation

// MARK: - Notes Repository Protocol

protocol NotesRepository {
    func all() async throws -> [Note]
    func find(id: UUID) async throws -> Note?
    func forDocument(documentId: UUID) async throws -> [Note]
    func save(_ note: Note) async throws
    func update(_ note: Note) async throws
    func delete(id: UUID) async throws
    func search(query: String) async throws -> [Note]
}

// MARK: - Local Notes Repository

final class LocalNotesRepository: NotesRepository {
    private let persistenceService: PersistenceServiceProtocol
    
    init(persistenceService: PersistenceServiceProtocol) {
        self.persistenceService = persistenceService
    }
    
    func all() async throws -> [Note] {
        try await persistenceService.loadAllNotes()
    }
    
    func find(id: UUID) async throws -> Note? {
        try? await persistenceService.loadNote(id: id)
    }
    
    func forDocument(documentId: UUID) async throws -> [Note] {
        try await persistenceService.loadNotes(for: documentId)
    }
    
    func save(_ note: Note) async throws {
        try await persistenceService.saveNote(note)
    }
    
    func update(_ note: Note) async throws {
        try await persistenceService.updateNote(note)
    }
    
    func delete(id: UUID) async throws {
        try await persistenceService.deleteNote(id: id)
    }
    
    func search(query: String) async throws -> [Note] {
        let allNotes = try await all()
        guard !query.isEmpty else { return allNotes }
        
        let lowercased = query.lowercased()
        return allNotes.filter { note in
            note.title.lowercased().contains(lowercased) ||
            note.content.lowercased().contains(lowercased) ||
            note.tags.contains { $0.lowercased().contains(lowercased) }
        }
    }
}

// MARK: - Mock Notes Repository

final class MockNotesRepository: NotesRepository {
    private var notes: [Note] = []
    
    init(notes: [Note] = []) {
        self.notes = notes
    }
    
    func all() async throws -> [Note] {
        notes
    }
    
    func find(id: UUID) async throws -> Note? {
        notes.first { $0.id == id }
    }
    
    func forDocument(documentId: UUID) async throws -> [Note] {
        notes.filter { $0.documentId == documentId }
    }
    
    func save(_ note: Note) async throws {
        notes.append(note)
    }
    
    func update(_ note: Note) async throws {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }
    }
    
    func delete(id: UUID) async throws {
        notes.removeAll { $0.id == id }
    }
    
    func search(query: String) async throws -> [Note] {
        guard !query.isEmpty else { return notes }
        let lowercased = query.lowercased()
        return notes.filter { $0.title.lowercased().contains(lowercased) }
    }
}
