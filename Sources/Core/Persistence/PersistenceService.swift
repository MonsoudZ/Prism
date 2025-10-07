import Foundation
actor PersistenceService {
    func fetchLibraryItems() async throws -> [LibraryItem] {
        [LibraryItem(id: UUID(), title: "Welcome to Prism")]
    }
}
