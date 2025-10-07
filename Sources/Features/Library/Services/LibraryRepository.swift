import Foundation

protocol LibraryRepository {
    func all() async throws -> [LibraryItem]
}

struct LocalLibraryRepository: LibraryRepository {
    let persistence: PersistenceService
    func all() async throws -> [LibraryItem] {
        try await persistence.loadLibraryItems()
    }
}
