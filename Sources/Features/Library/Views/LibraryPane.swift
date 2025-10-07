import SwiftUI

struct LibraryPane: View {
    @StateObject private var vm: LibraryViewModel
    init(vm: LibraryViewModel) { _vm = StateObject(wrappedValue: vm) }

    var body: some View {
        List(vm.items) { item in
            Text(item.title)
        }
        .task { await vm.load() }
    }
}
