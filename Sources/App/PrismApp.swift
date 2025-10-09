import SwiftUI

// MARK: - App Entry Point

@main
struct PrismApp: App {
    @StateObject private var appEnvironment = AppEnvironment.shared
    
    var body: some Scene {
        WindowGroup {
            CompositionRoot()
                .environmentObject(appEnvironment)
                .frame(minWidth: 900, minHeight: 650)
                .onAppear {
                    checkInitialization()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            PrismCommands()
        }
    }
    
    // MARK: - Initialization Check
    
    private func checkInitialization() {
        Log.info("Prism initialized successfully")
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
            
            Button("Close PDF") {
                NotificationCenter.default.post(name: .closePDF, object: nil)
            }
            .keyboardShortcut("w", modifiers: [.command])
        }
        
        // Edit Menu
        CommandGroup(after: .textEditing) {
            Button("New Note") {
                NotificationCenter.default.post(name: .addStickyNote, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            
            Button("Highlight") {
                NotificationCenter.default.post(name: .captureHighlight, object: nil)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
        }
        
        // View Menu
        CommandGroup(after: .sidebar) {
            Button("Toggle Library") {
                NotificationCenter.default.post(name: .toggleLibrary, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command])
            
            Button("Toggle Notes") {
                NotificationCenter.default.post(name: .toggleNotes, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command])
            
            Divider()
            
            Button("Find in PDF") {
                NotificationCenter.default.post(name: .toggleSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command])
        }
        
        // Help Menu
        CommandGroup(after: .help) {
            Button("Prism Help") {
                NotificationCenter.default.post(name: .showHelp, object: nil)
            }
            .keyboardShortcut("?", modifiers: [.command])
            
            Button("Show Onboarding") {
                NotificationCenter.default.post(name: .showOnboarding, object: nil)
            }
            
            Divider()
            
            Button("Settings…") {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
