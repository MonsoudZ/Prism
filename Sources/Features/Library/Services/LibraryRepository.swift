import Foundation

// MARK: - Library Repository Protocol

protocol LibraryRepository {
    func all() async throws -> [LibraryItem]
    func find(id: UUID) async throws -> LibraryItem?
    func save(_ item: LibraryItem) async throws
    func update(_ item: LibraryItem) async throws
    func delete(id: UUID) async throws
    func search(query: String) async throws -> [LibraryItem]
}

// MARK: - Local Repository Implementation

final class LocalLibraryRepository: LibraryRepository {
    private let persistenceService: PersistenceServiceProtocol
    
    init(persistenceService: PersistenceServiceProtocol) {
        self.persistenceService = persistenceService
    }
    
    // MARK: - CRUD Operations
    
    func all() async throws -> [LibraryItem] {
        // Load all documents and convert to LibraryItems
        let documents = try await persistenceService.loadAllDocuments()
        return documents.map { document in
            convertToLibraryItem(document)
        }
    }
    
    func find(id: UUID) async throws -> LibraryItem? {
        do {
            let document = try await persistenceService.loadDocument(id: id)
            return convertToLibraryItem(document)
        } catch PersistenceError.fileNotFound {
            return nil
        }
    }
    
    func save(_ item: LibraryItem) async throws {
        let document = convertToDocument(item)
        try await persistenceService.saveDocument(document)
    }
    
    func update(_ item: LibraryItem) async throws {
        let document = convertToDocument(item)
        try await persistenceService.updateDocument(document)
    }
    
    func delete(id: UUID) async throws {
        // Delete document metadata
        try await persistenceService.deleteDocument(id: id)
        
        // Delete associated PDF file
        if let item = try await find(id: id) {
            let pdfPath = item.url.lastPathComponent
            try? persistenceService.deletePDFFile(at: pdfPath)
        }
    }
    
    // MARK: - Search
    
    func search(query: String) async throws -> [LibraryItem] {
        let allItems = try await all()
        guard !query.isEmpty else { return allItems }
        
        let lowercased = query.lowercased()
        return allItems.filter { item in
            item.title.lowercased().contains(lowercased) ||
            item.tags.contains { $0.lowercased().contains(lowercased) } ||
            (item.author?.lowercased().contains(lowercased) ?? false)
        }
    }
    
    // MARK: - Conversion Helpers
    
    private func convertToLibraryItem(_ document: Document) -> LibraryItem {
        // Reconstruct URL from stored path
        let pdfURL: URL
        do {
            pdfURL = try persistenceService.loadPDFFile(at: document.filePath)
        } catch {
            // Fallback to a placeholder URL if file is missing
            pdfURL = URL(fileURLWithPath: document.filePath)
        }
        
        return LibraryItem(
            id: document.id,
            url: pdfURL,
            securityScopedBookmark: nil, // TODO: Store this in Document model
            title: document.title,
            author: nil, // TODO: Extract from PDF metadata
            pageCount: document.pageCount,
            fileSize: document.fileSize,
            addedDate: document.dateAdded,
            lastOpened: document.lastOpened,
            tags: document.tags,
            isPinned: document.isFavorite,
            thumbnailData: nil // TODO: Generate and cache
        )
    }
    
    private func convertToDocument(_ item: LibraryItem) -> Document {
        Document(
            id: item.id,
            title: item.title,
            filePath: item.url.lastPathComponent,
            fileSize: item.fileSize,
            pageCount: item.pageCount,
            dateAdded: item.addedDate,
            dateModified: Date(),
            lastOpened: item.lastOpened,
            currentPage: 0, // TODO: Track this
            tags: item.tags,
            isFavorite: item.isPinned,
            readingProgress: 0.0 // TODO: Calculate this
        )
    }
}

// MARK: - Mock Repository (for previews/tests)

final class MockLibraryRepository: LibraryRepository {
    private var items: [LibraryItem] = []
    
    init(items: [LibraryItem] = []) {
        self.items = items
    }
    
    func all() async throws -> [LibraryItem] {
        items
    }
    
    func find(id: UUID) async throws -> LibraryItem? {
        items.first { $0.id == id }
    }
    
    func save(_ item: LibraryItem) async throws {
        items.append(item)
    }
    
    func update(_ item: LibraryItem) async throws {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        }
    }
    
    func delete(id: UUID) async throws {
        items.removeAll { $0.id == id }
    }
    
    func search(query: String) async throws -> [LibraryItem] {
        guard !query.isEmpty else { return items }
        let lowercased = query.lowercased()
        return items.filter { $0.title.lowercased().contains(lowercased) }
    }
}
