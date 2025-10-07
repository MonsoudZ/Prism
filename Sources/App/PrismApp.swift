import SwiftUI

@main
struct PrismApp: App {
    private let comp = CompositionRoot()

    var body: some Scene {
        WindowGroup {
            comp.makeRootView()
        }
        .commands { /* AppCommands later */ }
    }
}
