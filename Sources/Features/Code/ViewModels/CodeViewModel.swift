//
//  CodeViewModel.swift
//  Prism
//
//  Created by Monsoud Zanaty on 10/4/25.
//

import Foundation
import Combine
import UniformTypeIdentifiers
import AppKit

/// High-level mode for the code area (mirrors your UI segmented control).
enum CodePaneMode {
    case scratch
    case monaco
}

/// Single source of truth for all code-editing state and actions used by CodePane.
/// - Owns: selected language, current code buffer, output, run state, filename, Monaco fallback flag.
/// - Performs: execute code (via runner), save/load (via NSSave/Open), simple exports, debounced autosave.
/// - Collaborators: `Shell` (process runner), `LoadingStateManager` (user feedback).
@MainActor
final class CodeViewModel: ObservableObject {

    // MARK: - Published UI State

    /// Current pane (Scratch or Monaco). The view can bind to this if needed.
    @Published var mode: CodePaneMode = .scratch

    /// Currently selected language across both editors.
    @Published var language: CodeLang = .python {
        didSet { applyDefaultIfEmpty() }
    }

    /// The active code buffer (shared by Scratch + Monaco).
    @Published var code: String = "" {
        didSet { scheduleAutosave() }
    }

    /// Process output or error text shown in the right panel.
    @Published var output: String = ""

    /// Running flag for disabling buttons and showing progress.
    @Published var isRunning: Bool = false

    /// File name label displayed in the toolbar (not a path).
    @Published var currentFileName: String = "untitled.py"

    /// When the Monaco CDN fails (offline, blocked), views can flip to TextEditor.
    @Published var useMonacoFallback: Bool = false

    // MARK: - Settings / Persistence

    /// In-memory debounce for autosave.
    private var autosaveWorkItem: DispatchWorkItem?
    /// Where we persist the last buffer per language (UserDefaults key prefix).
    private let autosaveKeyPrefix = "Prism.Code.autosave."

    // MARK: - Lifecycle

    init() {
        // Load last saved buffer for default language (if any).
        loadAutosavedBuffer(for: language)
        applyDefaultIfEmpty()
        updateDefaultFilename()
    }


    // MARK: - File Operations (Save / Load)

    /// Save the current buffer to a user-chosen location.
    func saveFilePanel() {
        LoadingStateManager.shared.startFileOperation("Saving file...")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: language.fileExtension) ?? .plainText]
        panel.nameFieldStringValue = currentFileName

        panel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = panel.url {
                self.save(to: url)
            }
            LoadingStateManager.shared.stopFileOperation()
        }
    }

    /// Load a file from disk and adopt its contents and language.
    func loadFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        panel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = panel.url {
                self.load(from: url)
            }
        }
    }

    // MARK: - Export Helpers (lightweight scaffolds)

    func exportAsStandaloneFilePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: language.fileExtension) ?? .plainText]
        panel.nameFieldStringValue = currentFileName

        panel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = panel.url {
                do {
                    try self.code.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    self.output = "Error saving file: \(error.localizedDescription)"
                }
            }
        }
    }

    func exportToVSCodeProjectPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select VSCode Project Folder"

        panel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let base = panel.url {
                self.exportToVSCodeProject(at: base)
            }
        }
    }

    // MARK: - Monaco Fallback

    /// If Monaco doesn't report ready within a timeout, views can call this.
    func triggerMonacoFallback() {
        useMonacoFallback = true
        LoadingStateManager.shared.stopMonacoLoading()
    }

    /// Mark Monaco as ready (stop loading spinner).
    func monacoReady() {
        LoadingStateManager.shared.stopMonacoLoading()
    }

    // MARK: - Private: Save/Load

    private func save(to url: URL) {
        do {
            try code.write(to: url, atomically: true, encoding: .utf8)
            currentFileName = url.lastPathComponent
        } catch {
            output = "Error saving file: \(error.localizedDescription)"
        }
    }

    private func load(from url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            code = content
            currentFileName = url.lastPathComponent

            // Adopt language from extension if possible
            let ext = url.pathExtension.lowercased()
            if let lang = CodeLang.allCases.first(where: { $0.fileExtension == ext }) {
                language = lang
            }
        } catch {
            output = "Error loading file: \(error.localizedDescription)"
        }
    }

    // MARK: - Private: VSCode Export

    private func exportToVSCodeProject(at baseFolder: URL) {
        let projectName = currentFileName.components(separatedBy: ".").first ?? "prism-project"
        let projectPath = baseFolder.appendingPathComponent(projectName)

        do {
            try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
            // Source file
            let source = projectPath.appendingPathComponent(currentFileName)
            try code.write(to: source, atomically: true, encoding: .utf8)

            // .vscode/settings.json
            let settingsDir = projectPath.appendingPathComponent(".vscode")
            try FileManager.default.createDirectory(at: settingsDir, withIntermediateDirectories: true)
            let settings = """
            {
              "files.associations": {
                "*.\(language.fileExtension)": "\(monacoLanguage(language))"
              }
            }
            """
            try settings.write(to: settingsDir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        } catch {
            output = "Error creating VSCode project: \(error.localizedDescription)"
        }
    }

    // MARK: - Autosave

    /// Debounce writing the current buffer to UserDefaults per language.
    private func scheduleAutosave() {
        autosaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let key = self.autosaveKeyPrefix + self.language.fileExtension
            UserDefaults.standard.set(self.code, forKey: key)
        }
        autosaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func loadAutosavedBuffer(for lang: CodeLang) {
        let key = autosaveKeyPrefix + lang.fileExtension
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            code = saved
        }
    }

    // MARK: - Helpers

    private func applyDefaultIfEmpty() {
        guard code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        code = defaultTemplate(for: language)
        updateDefaultFilename()
    }

    private func updateDefaultFilename() {
        if currentFileName == "untitled.py" || currentFileName.hasPrefix("untitled.") {
            currentFileName = "untitled.\(language.fileExtension)"
        }
    }

    private func defaultTemplate(for lang: CodeLang) -> String {
        switch lang {
        case .python:     return "# Example:\nprint('hello from Prism!')"
        case .ruby:       return "# Example:\nputs 'hello from Prism!'"
        case .node, .javascript:
            return "// Example:\nconsole.log('hello from Prism!');"
        case .swift:      return "// Example:\nprint(\"hello from Prism!\")"
        case .bash:       return "# Example:\necho 'hello from Prism!'"
        case .go:
            return """
            // NOTE: Go toolchain execution is disabled by default in Prism.
            package main
            import "fmt"
            func main(){ fmt.Println("hello from Prism!") }
            """
        case .c:
            return """
            // NOTE: C toolchain execution is disabled by default in Prism.
            #include <stdio.h>
            int main(){ printf("hello from Prism!\\n"); return 0; }
            """
        case .cpp:
            return """
            // NOTE: C++ toolchain execution is disabled by default in Prism.
            #include <iostream>
            int main(){ std::cout << "hello from Prism!" << std::endl; return 0; }
            """
        case .rust:
            return """
            // NOTE: Rust toolchain execution is disabled by default in Prism.
            fn main(){ println!("hello from Prism!"); }
            """
        case .java:
            return """
            // NOTE: Java toolchain execution is disabled by default in Prism.
            public class Main { public static void main(String[] args){ System.out.println("hello from Prism!"); } }
            """
        case .sql:
            return """
            -- NOTE: SQLite execution requires a DB; disabled by default in Prism.
            SELECT 'hello from Prism!' AS message;
            """
        }
    }

    private func monacoLanguage(_ lang: CodeLang) -> String {
        switch lang {
        case .python: return "python"
        case .ruby: return "ruby"
        case .node, .javascript: return "javascript"
        case .swift: return "swift"
        case .bash: return "shell"
        case .go: return "go"
        case .c: return "c"
        case .cpp: return "cpp"
        case .rust: return "rust"
        case .java: return "java"
        case .sql: return "sql"
        }
    }
}
