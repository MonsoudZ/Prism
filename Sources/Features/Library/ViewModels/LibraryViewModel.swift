import Foundation
import Combine

// MARK: - Sort & Filter Options

enum LibrarySortOption: String, CaseIterable {
    case dateAdded = "Date Added"
    case dateModified = "Recently Opened"
    case title = "Title"
    case fileSize = "File Size"
    
    func sort(_ items: [LibraryItem]) -> [LibraryItem] {
        switch self {
        case .dateAdded:
            return items.sorted { $0.addedDate > $1.addedDate }
        case .dateModified:
            return items.sorted { (i1, i2) in
                guard let d1 = i1.lastOpened, let d2 = i2.lastOpened else {
                    return i1.lastOpened != nil
                }
                return d1 > d2
            }
        case .title:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .fileSize:
            return items.sorted { $0.fileSize > $1.fileSize }
        }
    }
}

enum LibraryFilterOption: String, CaseIterable {
    case all = "All Documents"
    case pinned = "Pinned"
    case recent = "Recently Opened"
    case pdfs = "PDFs Only"
    
    func filter(_ items: [LibraryItem]) -> [LibraryItem] {
        switch self {
        case .all:
            return items
        case .pinned:
            return items.filter { $0.isPinned }
        case .recent:
            return items.filter { $0.lastOpened != nil }
        case .pdfs:
            return items.filter { $0.isPDF }
        }
    }
}

enum LibraryViewStyle: String, CaseIterable {
    case grid = "Grid"
    case list = "List"
}

// MARK: - Library View Model

@MainActor
final class LibraryViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var filteredItems: [LibraryItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    // MARK: - UI State
    
    @Published var searchQuery: String = ""
    @Published var selectedSort: LibrarySortOption = .dateAdded
    @Published var selectedFilter: LibraryFilterOption = .all
    @Published var viewStyle: LibraryViewStyle = .grid
    @Published var selectedItems: Set<UUID> = []
    
    // MARK: - Dependencies
    
    private let repo: LibraryRepository
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(repo: LibraryRepository) {
        self.repo = repo
        setupObservers()
    }
    
    private func setupObservers() {
        // Auto-update filtered items when any relevant state changes
        Publishers.CombineLatest4(
            $items,
            $searchQuery,
            $selectedSort,
            $selectedFilter
        )
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] items, query, sort, filter in
            self?.applyFiltersAndSort(items: items, query: query, sort: sort, filter: filter)
        }
        .store(in: &cancellables)
        
        // Listen for document changes
        NotificationCenter.default.publisher(for: .prismDocumentAdded)
            .sink { [weak self] _ in
                Task { await self?.load() }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .prismDocumentUpdated)
            .sink { [weak self] _ in
                Task { await self?.load() }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .prismDocumentDeleted)
            .sink { [weak self] _ in
                Task { await self?.load() }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Loading
    
    func load() async {
        isLoading = true
        error = nil
        
        do {
            items = try await repo.all()
        } catch {
            self.error = error
            items = []
            Log.error("Failed to load library: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    // MARK: - Filtering & Sorting
    
    private func applyFiltersAndSort(
        items: [LibraryItem],
        query: String,
        sort: LibrarySortOption,
        filter: LibraryFilterOption
    ) {
        var result = items
        
        // Apply filter
        result = filter.filter(result)
        
        // Apply search
        if !query.isEmpty {
            let lowercased = query.lowercased()
            result = result.filter { item in
                item.title.lowercased().contains(lowercased) ||
                item.tags.contains { $0.lowercased().contains(lowercased) } ||
                (item.author?.lowercased().contains(lowercased) ?? false)
            }
        }
        
        // Apply sort
        result = sort.sort(result)
        
        self.filteredItems = result
    }
    
    // MARK: - Actions
    
    func togglePin(itemId: UUID) async {
        guard let item = items.first(where: { $0.id == itemId }) else { return }
        
        // Create updated item with toggled pin
        let updatedItem = LibraryItem(
            id: item.id,
            url: item.url,
            securityScopedBookmark: item.securityScopedBookmark,
            title: item.title,
            author: item.author,
            pageCount: item.pageCount,
            fileSize: item.fileSize,
            addedDate: item.addedDate,
            lastOpened: item.lastOpened,
            tags: item.tags,
            isPinned: !item.isPinned,
            thumbnailData: item.thumbnailData
        )
        
        do {
            try await repo.update(updatedItem)
            await load()
        } catch {
            self.error = error
            Log.error("Failed to toggle pin: \(error.localizedDescription)")
        }
    }
    
    func delete(itemId: UUID) async {
        do {
            try await repo.delete(id: itemId)
            await load()
            
            NotificationCenter.default.post(
                name: .prismDocumentDeleted,
                object: nil,
                userInfo: ["documentId": itemId]
            )
        } catch {
            self.error = error
            Log.error("Failed to delete item: \(error.localizedDescription)")
        }
    }
    
    func deleteSelected() async {
        for id in selectedItems {
            await delete(itemId: id)
        }
        selectedItems.removeAll()
    }
    
    func updateTags(itemId: UUID, tags: [String]) async {
        guard let item = items.first(where: { $0.id == itemId }) else { return }
        
        let updatedItem = LibraryItem(
            id: item.id,
            url: item.url,
            securityScopedBookmark: item.securityScopedBookmark,
            title: item.title,
            author: item.author,
            pageCount: item.pageCount,
            fileSize: item.fileSize,
            addedDate: item.addedDate,
            lastOpened: item.lastOpened,
            tags: tags,
            isPinned: item.isPinned,
            thumbnailData: item.thumbnailData
        )
        
        do {
            try await repo.update(updatedItem)
            await load()
        } catch {
            self.error = error
            Log.error("Failed to update tags: \(error.localizedDescription)")
        }
    }
    
    func importDocument(from url: URL) async {
        // TODO: This will need PDF service to extract metadata
        // For now, create a basic item
        let item = LibraryItem(
            url: url,
            title: url.deletingPathExtension().lastPathComponent,
            pageCount: 0, // Need PDFService to extract
            fileSize: (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        )
        
        do {
            try await repo.save(item)
            await load()
            
            NotificationCenter.default.post(
                name: .prismDocumentAdded,
                object: item
            )
        } catch {
            self.error = error
            Log.error("Failed to import document: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Selection
    
    func toggleSelection(itemId: UUID) {
        if selectedItems.contains(itemId) {
            selectedItems.remove(itemId)
        } else {
            selectedItems.insert(itemId)
        }
    }
    
    func selectAll() {
        selectedItems = Set(filteredItems.map { $0.id })
    }
    
    func deselectAll() {
        selectedItems.removeAll()
    }
    
    var isInSelectionMode: Bool {
        !selectedItems.isEmpty
    }
    
    // MARK: - Statistics
    
    var totalDocuments: Int {
        items.count
    }
    
    var totalStorageUsed: Int64 {
        items.reduce(0) { $0 + $1.fileSize }
    }
    
    var formattedStorageUsed: String {
        ByteCountFormatter.string(fromByteCount: totalStorageUsed, countStyle: .file)
    }
    
    var pinnedItems: [LibraryItem] {
        items.filter { $0.isPinned }
    }
    
    var recentItems: [LibraryItem] {
        items
            .filter { $0.lastOpened != nil }
            .sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let prismDocumentAdded = Notification.Name("Prism.documentAdded")
    static let prismDocumentUpdated = Notification.Name("Prism.documentUpdated")
    static let prismDocumentDeleted = Notification.Name("Prism.documentDeleted")
    static let prismAnnotationAdded = Notification.Name("Prism.annotationAdded")
    static let prismAnnotationUpdated = Notification.Name("Prism.annotationUpdated")
    static let prismAnnotationDeleted = Notification.Name("Prism.annotationDeleted")
}
