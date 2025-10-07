import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []
    private let repo: LibraryRepository

    init(repo: LibraryRepository) { self.repo = repo }

    func load() async {
        do { items = try await repo.all() }
        catch { items = []; /* TODO: surface AppError */ }
    }
}
