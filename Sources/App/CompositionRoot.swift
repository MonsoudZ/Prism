import SwiftUI

struct CompositionRoot {
    // Core singletons
    let persistence = PersistenceService()               // your Core/Persistence
    let crashReporter = CrashReportingService()

    // Feature factories
    func makeLibraryRepo() -> LibraryRepository {
        LocalLibraryRepository(persistence: persistence)
    }

    @MainActor
    func makeLibraryView() -> some View {
        let vm = LibraryViewModel(repo: makeLibraryRepo())
        return LibraryPane(vm: vm)
    }

    // Swap this later for a real router
    @MainActor
    func makeRootView() -> some View { makeLibraryView() }
}
