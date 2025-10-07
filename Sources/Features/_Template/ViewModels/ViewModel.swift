import Foundation
import Combine

@MainActor
final class ViewModel: ObservableObject {
    @Published private(set) var items: [Entity] = []
    private let repo: Repository

    init(repo: Repository) {            // <- no default
        self.repo = repo
    }

    func load() async {
        items = (try? await repo.all()) ?? []
    }
}
