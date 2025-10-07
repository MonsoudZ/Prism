import SwiftUI
import PDFKit
import Combine

// MARK: - App Entry Point

@main
struct PrismApp: App {
    @StateObject private var appEnvironment = AppEnvironment.shared
    
    init() {
        // Initialize persistence on app launch
        do {
            try PersistenceService.initialize()
        } catch {
            UserDefaults.standard.set(error.localizedDescription, forKey: "initializationError")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            CompositionRoot()
                .environmentObject(appEnvironment)
                .frame(minWidth: 900, minHeight: 650)
                .onAppear(perform: checkInitializationError)
                .alert("Initialization Error", isPresented: $appEnvironment.showingInitError) {
                    Button("OK") {
                        appEnvironment.showingInitError = false
                        clearInitializationError()
                    }
                    Button("Retry") {
                        retryInitialization()
                    }
                } message: {
                    Text(appEnvironment.initializationError ?? "An unknown error occurred during app initialization.")
                }
        }
        .windowStyle(.titleBar)
        .commands {
            PrismCommands()
        }
    }
    
    // MARK: - Error Handling
    
    private func checkInitializationError() {
        if let error = UserDefaults.standard.string(forKey: "initializationError") {
            appEnvironment.initializationError = error
            appEnvironment.showingInitError = true
        }
    }
    
    private func clearInitializationError() {
        UserDefaults.standard.removeObject(forKey: "initializationError")
        appEnvironment.initializationError = nil
    }
    
    private func retryInitialization() {
        clearInitializationError()
        do {
            try PersistenceService.initialize()
            appEnvironment.enhancedToastCenter.showSuccess(
                "Initialization Succeeded",
                "App storage and services are ready.",
                category: .system
            )
        } catch {
            appEnvironment.initializationError = error.localizedDescription
            appEnvironment.showingInitError = true
        }
    }
}

// MARK: - App Commands

struct PrismCommands: Commands {
    var body: some Commands {
        // File Menu
        CommandGroup(after: .newItem) {
            Button("Open PDF…") {
                NotificationCenter.default.post(name: .openPDF, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command])
            
            Button("Import PDFs…") {
                NotificationCenter.default.post(name: .importPDFs, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command])
            
            Divider()
            
            Button("New Sketch Page") {
                NotificationCenter.default.post(name: .newSketchPage, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        
        // Edit Menu
        CommandGroup(after: .textEditing) {
            Button("Highlight → Note") {
                NotificationCenter.default.post(name: .captureHighlight, object: nil)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            
            Button("Add Sticky Note") {
                NotificationCenter.default.post(name: .addStickyNote, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
        
        // View Menu
        CommandGroup(after: .appVisibility) {
            Button("Toggle Search") {
                NotificationCenter.default.post(name: .toggleSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command])
            
            Button("Toggle Library") {
                NotificationCenter.default.post(name: .toggleLibrary, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command])
            
            Button("Toggle Notes") {
                NotificationCenter.default.post(name: .toggleNotes, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command])
            
            Divider()
            
            Button("Close PDF") {
                NotificationCenter.default.post(name: .closePDF, object: nil)
            }
            .keyboardShortcut("w", modifiers: [.command])
        }
        
        // Help Menu
        CommandGroup(after: .help) {
            Button("Show Help") {
                NotificationCenter.default.post(name: .showHelp, object: nil)
            }
            .keyboardShortcut("?", modifiers: [.command])
            
            Button("Show Onboarding") {
                NotificationCenter.default.post(name: .showOnboarding, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            
            Divider()
            
            Button("About Prism") {
                NotificationCenter.default.post(name: .showAbout, object: nil)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openPDF = Notification.Name("Prism.openPDF")
    static let importPDFs = Notification.Name("Prism.importPDFs")
    static let closePDF = Notification.Name("Prism.closePDF")
    static let toggleSearch = Notification.Name("Prism.toggleSearch")
    static let toggleLibrary = Notification.Name("Prism.toggleLibrary")
    static let toggleNotes = Notification.Name("Prism.toggleNotes")
    static let captureHighlight = Notification.Name("Prism.captureHighlight")
    static let addStickyNote = Notification.Name("Prism.addStickyNote")
    static let newSketchPage = Notification.Name("Prism.newSketchPage")
    static let showHelp = Notification.Name("Prism.showHelp")
    static let showOnboarding = Notification.Name("Prism.showOnboarding")
    static let showAbout = Notification.Name("Prism.showAbout")
    static let pdfLoadError = Notification.Name("Prism.pdfLoadError")
    static let sessionCorrupted = Notification.Name("Prism.sessionCorrupted")
    static let dataRecovery = Notification.Name("Prism.dataRecovery")
    static let memoryPressure = Notification.Name("Prism.memoryPressure")
    static let currentPDFURLDidChange = Notification.Name("Prism.currentPDFURLDidChange")
    static let showToast = Notification.Name("Prism.showToast")
}
