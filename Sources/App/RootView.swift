import SwiftUI

/// App-level container. Keep it concrete to avoid unresolved generic symbols.
struct RootView: View {
    var body: some View {
        CompositionRoot()
    }
}

#Preview { RootView() }
