//
//  Environment.swift
//  Prism
//
//  Central app environment (singleton) + global notifications.
//  Owns light-weight, cross-window state and coordinates high-level actions.
//
//  Why we need this
//  ----------------
//  • One source of truth for window-level UI flags (settings/help/onboarding).
//  • A single place to publish shared models later (e.g., PDFViewModel).
//  • Central definition of Notification.Name used by menus/commands.
//  • Keeps initialization and first-launch logic out of views.
//
//  Notes
//  -----
//  • The environment is @MainActor since UI state is published here.
//  • Add more shared view models as your Features solidify (e.g., NotesViewModel).
//

import SwiftUI
import Combine
import AppKit

// MARK: - Global App Notifications
// Define once; use everywhere (menus, toolbars, panes). This fixes
// “NSNotification.Name has no member …” build errors and avoids stringly-typed names.

extension Notification.Name {
    // File actions
    static let openPDF        = Notification.Name("Prism.openPDF")
    static let importPDFs     = Notification.Name("Prism.importPDFs")
    static let closePDF       = Notification.Name("Prism.closePDF")

    // Panels & view toggles
    static let toggleLibrary  = Notification.Name("Prism.toggleLibrary")
    static let toggleNotes    = Notification.Name("Prism.toggleNotes")
    static let toggleSearch   = Notification.Name("Prism.toggleSearch")

    // Notes & annotations
    static let addStickyNote     = Notification.Name("Prism.addStickyNote")
    static let captureHighlight  = Notification.Name("Prism.captureHighlight")

    // App chrome
    static let showHelp       = Notification.Name("Prism.showHelp")
    static let showOnboarding = Notification.Name("Prism.showOnboarding")
    static let showSettings   = Notification.Name("Prism.showSettings")

    // Feedback / toasts (optional – wire to your toast center if/when you add one)
    static let showToast      = Notification.Name("Prism.showToast")
}

// MARK: - AppEnvironment
// Holds shared UI state and (optionally) shared models. Keep it light.
// Prefer each Feature to own its own ViewModel; re-expose here only if multiple
// windows/scenes must share the same instance.

@MainActor
final class AppEnvironment: ObservableObject {

    // Singleton for easy injection across windows
    static let shared = AppEnvironment()

    // MARK: Shared View Models (add as your Feature modules stabilize)
    // Example: expose PDF only if you truly want a single, shared controller.
    // Otherwise instantiate per-View in each Feature.
    //
    // @Published var pdf: PDFViewModel = .init()

    // MARK: Window/UI Flags
    @Published var isShowingHelp        = false
    @Published var isShowingSettings    = false
    @Published var isShowingOnboarding  = false

    // Panels (library/notes/search) – keep these if you want app-wide toggles
    @Published var isLibraryVisible     = true
    @Published var isNotesVisible       = true
    @Published var isSearchVisible      = false

    // Internal
    private var cancellables = Set<AnyCancellable>()

    // MARK: Init
    private init() {
        configureFirstLaunch()
        wireNotifications()
    }

    // MARK: First Launch / Onboarding
    private func configureFirstLaunch() {
        let hasLaunchedKey = "Prism.hasLaunched"
        let didSeeOnboardingKey = "Prism.didSeeOnboarding"

        let hasLaunched = UserDefaults.standard.bool(forKey: hasLaunchedKey)
        let didSee = UserDefaults.standard.bool(forKey: didSeeOnboardingKey)

        if !hasLaunched || !didSee {
            isShowingOnboarding = true
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
        }
    }

    func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: "Prism.didSeeOnboarding")
        isShowingOnboarding = false
    }

    // MARK: Notification Wiring
    // Listen to simple app-wide events (menu commands, toolbar actions).
    private func wireNotifications() {
        let nc = NotificationCenter.default

        nc.publisher(for: .showHelp)
            .sink { [weak self] _ in self?.openHelp() }
            .store(in: &cancellables)

        nc.publisher(for: .showSettings)
            .sink { [weak self] _ in self?.openSettings() }
            .store(in: &cancellables)

        nc.publisher(for: .showOnboarding)
            .sink { [weak self] _ in self?.isShowingOnboarding = true }
            .store(in: &cancellables)

        nc.publisher(for: .toggleLibrary)
            .sink { [weak self] _ in self?.isLibraryVisible.toggle() }
            .store(in: &cancellables)

        nc.publisher(for: .toggleNotes)
            .sink { [weak self] _ in self?.isNotesVisible.toggle() }
            .store(in: &cancellables)

        nc.publisher(for: .toggleSearch)
            .sink { [weak self] _ in self?.isSearchVisible.toggle() }
            .store(in: &cancellables)
    }

    // MARK: Commands Helpers
    func openSettings() { isShowingSettings = true }
    func openHelp()     { isShowingHelp = true }

    // MARK: Window Management
    // Open a new window using your root view. Adjust the root as your composition evolves.
    func openNewWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // Replace `CompositionRoot()` with your actual root SwiftUI view
        window.contentView = NSHostingView(rootView: CompositionRoot().environmentObject(self))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Data Utilities (stubs)
    // Fill these in once your persistence layer is ready.
    func clearAllData() {
        // TODO: broadcast notifications or call into shared models to clear caches/state.
        // Example:
        // pdf.clearSession()
        // NotificationCenter.default.post(name: .someCacheEviction, object: nil)
    }

    func exportAllData() -> URL? {
        // TODO: Build a zip bundle of your envelopes/cache as needed.
        // Return a temporary URL to share/save.
        return nil
    }

    func importData(from url: URL) {
        // TODO: Read bundle and hydrate models accordingly.
    }
}
