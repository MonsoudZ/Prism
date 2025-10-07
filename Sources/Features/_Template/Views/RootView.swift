import SwiftUI

struct RootView: View {
    @StateObject private var vm: ViewModel

    init(repo: Repository) {                     // accepts non-actor repo
        _vm = StateObject(wrappedValue: ViewModel(repo: repo)) // VM made on main actor
    }

    var body: some View {
        List(vm.items) { _ in Text("Item") }
            .task { await vm.load() }
    }
}
