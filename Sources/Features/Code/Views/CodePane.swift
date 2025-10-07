import SwiftUI
import WebKit
import UniformTypeIdentifiers
import AppKit
import Foundation

// MARK: - Code Pane (Scratchpad + Monaco)
// A simple segmented control swaps between a quick "Scratch" runner and the Monaco web editor.
// Both share an "Output" panel and use LoadingStateManager for progress feedback.
struct CodePane: View {
    @State private var mode: CodeMode = .scratch
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("Scratchpad").tag(CodeMode.scratch)
                Text("Monaco").tag(CodeMode.monaco)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch mode {
            case .scratch:
                ScratchRunner()
            case .monaco:
                MonacoWebEditor()
            }
        }
    }
}

enum CodeMode { case scratch, monaco }

// MARK: - Scratch Runner
// A minimal REPL-ish experience that writes the code to a temp file and executes it.
// We keep the runner conservative for sandboxed macOS: Python/Ruby/Node/Swift/Bash are supported.
// Other compiled languages are stubbed with a message (you can expand later).
struct ScratchRunner: View {
    @State private var language: CodeLang = .python
    @State private var code: String = ""
    @State private var output: String = ""
    @State private var isRunning = false

    private var defaultCode: String {
        switch language {
        case .python:     return "# Example:\nprint('hello from Prism!')"
        case .ruby:       return "# Example:\nputs 'hello from Prism!'"
        case .node, .javascript:
            return "// Example:\nconsole.log('hello from Prism!');"
        case .swift:      return "// Example:\nprint(\"hello from Prism!\")"
        case .bash:       return "# Example:\necho 'hello from Prism!'"
        case .go:
            return """
            // NOTE: Go run requires a file on disk; Prism runner stubs this for now.
            package main
            import "fmt"
            func main(){ fmt.Println("hello from Prism!") }
            """
        case .c:
            return """
            // NOTE: Compiling C requires toolchain presence; Prism runner stubs this for now.
            #include <stdio.h>
            int main(){ printf("hello from Prism!\\n"); return 0; }
            """
        case .cpp:
            return """
            // NOTE: Compiling C++ requires toolchain presence; Prism runner stubs this for now.
            #include <iostream>
            int main(){ std::cout << "hello from Prism!" << std::endl; return 0; }
            """
        case .rust:
            return """
            // NOTE: Rust toolchain not invoked by default; Prism runner stubs this for now.
            fn main(){ println!("hello from Prism!"); }
            """
        case .java:
            return """
            // NOTE: Java toolchain not invoked by default; Prism runner stubs this for now.
            public class Main { public static void main(String[] args){ System.out.println("hello from Prism!"); } }
            """
        case .sql:
            return """
            -- NOTE: SQLite scripting needs a db file; Prism runner stubs this for now.
            SELECT 'hello from Prism!' as message;
            """
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("Language", selection: $language) {
                    ForEach(CodeLang.allCases, id: \.self) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 150)

                Spacer()
                Button(isRunning ? "Running…" : "Run") { run() }
                    .disabled(isRunning)
            }
            .padding(8)

            Divider()

            // Code input
            TextEditor(text: $code)
                .font(.system(.body, design: .monospaced))
                .padding(8)

            Divider()

            // Output panel
            ScrollView {
                Text(output)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            if code.isEmpty { code = defaultCode }
        }
        .onChange(of: language) {
            code = defaultCode
        }
    }

    private func run() {
        isRunning = true
        output = ""
        LoadingStateManager.shared.startLoading(.general, message: "Running \(language.rawValue) code...")

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Shell.run(language: language, code: code)
            DispatchQueue.main.async {
                self.output = result
                self.isRunning = false
                LoadingStateManager.shared.stopLoading(.general)
            }
        }
    }
}

// MARK: - Languages supported by UI
enum CodeLang: String, CaseIterable {
    case python = "Python"
    case ruby = "Ruby"
    case node = "Node.js"
    case swift = "Swift"
    case javascript = "JavaScript"
    case bash = "Bash"
    case go = "Go"
    case c = "C"
    case cpp = "C++"
    case rust = "Rust"
    case java = "Java"
    case sql = "SQL"

    var fileExtension: String {
        switch self {
        case .python: return "py"
        case .ruby: return "rb"
        case .node, .javascript: return "js"
        case .swift: return "swift"
        case .bash: return "sh"
        case .go: return "go"
        case .c: return "c"
        case .cpp: return "cpp"
        case .rust: return "rs"
        case .java: return "java"
        case .sql: return "sql"
        }
    }
}

// MARK: - Monaco Editor (WebView)
// Loads Monaco from CDN; if it fails within 3s, falls back to a local TextEditor.
// Provides basic Save/Load/Export commands and a right-side Output panel.
// NOTE: In a strict sandbox/offline environments the CDN may fail → fallback kicks in.
struct MonacoWebEditor: View {
    @AppStorage("monacoCode") private var savedCode: String = ""
    @State private var useFallback = false
    @State private var selectedLanguage: CodeLang = .python
    @State private var output: String = ""
    @State private var isRunning = false
    @State private var showFileManager = false
    @State private var currentFileName = "untitled.\(CodeLang.python.fileExtension)"
    @State private var showExportOptions = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(CodeLang.allCases, id: \.self) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 140)

                Button("Run") { executeCode() }.disabled(isRunning)
                Button("Save") { saveFile() }
                Button("Load") { showFileManager = true }
                Button("Export") { showExportOptions = true }

                Spacer()

                Text(currentFileName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Editor + Output
            HStack(spacing: 0) {
                // Editor
                VStack(spacing: 0) {
                    if useFallback {
                        FallbackCodeEditor(code: $savedCode)
                    } else {
                        WebViewHTML(
                            html: monacoHTML(initial: savedCode, language: monacoLanguage(selectedLanguage)),
                            savedCode: savedCode,
                            language: monacoLanguage(selectedLanguage)
                        ) { newCode in
                            savedCode = newCode
                        }
                        .onAppear {
                            LoadingStateManager.shared.startMonacoLoading("Initializing Monaco editor...")
                            // If not ready in 3s, fall back:
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                if !useFallback {
                                    useFallback = true
                                    LoadingStateManager.shared.stopMonacoLoading()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Output Panel
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Output")
                            .font(.headline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        Spacer()
                        Button("Clear") { output = "" }
                            .font(.caption)
                            .padding(.horizontal, 8)
                    }
                    .background(Color(NSColor.controlBackgroundColor))

                    ScrollView {
                        Text(output)
                            .font(.system(.footnote, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                }
                .frame(width: 320)
            }
        }
        .sheet(isPresented: $showFileManager) {
            FileManagerView(
                selectedLanguage: $selectedLanguage,
                savedCode: $savedCode,
                currentFileName: $currentFileName
            )
        }
        .sheet(isPresented: $showExportOptions) {
            ExportOptionsView(
                code: savedCode,
                language: selectedLanguage,
                fileName: currentFileName
            )
        }
        .onChange(of: selectedLanguage) {
            // If needed you can re-render Monaco with a new language.
            // In this simple approach we just leave the editor as-is;
            // advanced: send JS to change model language without reload.
        }
    }

    // MARK: Run from Monaco
    private func executeCode() {
        isRunning = true
        output = ""
        LoadingStateManager.shared.startLoading(.general, message: "Running \(selectedLanguage.rawValue) code...")

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Shell.run(language: selectedLanguage, code: savedCode)
            DispatchQueue.main.async {
                self.output = result
                self.isRunning = false
                LoadingStateManager.shared.stopLoading(.general)
            }
        }
    }

    // MARK: Save (NSSavePanel)
    private func saveFile() {
        LoadingStateManager.shared.startFileOperation("Saving file...")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: selectedLanguage.fileExtension) ?? .plainText]
        panel.nameFieldStringValue = currentFileName

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try savedCode.write(to: url, atomically: true, encoding: .utf8)
                    currentFileName = url.lastPathComponent
                    LoadingStateManager.shared.stopFileOperation()
                } catch {
                    // You can also route this through your toast/error manager
                    print("Error saving file: \(error.localizedDescription)")
                    LoadingStateManager.shared.stopFileOperation()
                }
            } else {
                LoadingStateManager.shared.stopFileOperation()
            }
        }
    }

    // MARK: Monaco HTML
    private func monacoHTML(initial: String, language: String) -> String {
        // Keep inline & minimal. We rely on CDN; fallback will kick in if blocked.
        let escaped = initial
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <style>
            html,body,#container{height:100%;margin:0}
            #container{display:flex;flex-direction:column}
            #editor{flex:1}
          </style>
          <script src="https://cdn.jsdelivr.net/npm/monaco-editor@0.52.0/min/vs/loader.js"></script>
          <script>
            require.config({ paths: { 'vs': 'https://cdn.jsdelivr.net/npm/monaco-editor@0.52.0/min/vs' } });
            window._code = `\(escaped)`;
            window._language = '\(language)';
            function notifyReady(){ try { window.webkit.messageHandlers.editorReady.postMessage('ready'); } catch(e){} }
            function notifyError(e){ try { window.webkit.messageHandlers.editorError.postMessage(String(e)); } catch(_){} }
            function notifyChange(text){ try { window.webkit.messageHandlers.codeChanged.postMessage(text); } catch(_){} }

            require(['vs/editor/editor.main'], function() {
              try {
                window.editor = monaco.editor.create(document.getElementById('editor'), {
                  value: window._code,
                  language: window._language,
                  automaticLayout: true,
                  theme: 'vs-dark',
                  minimap: { enabled: true },
                  wordWrap: 'on',
                  lineNumbers: 'on',
                  folding: true,
                  bracketPairColorization: { enabled: true },
                  formatOnPaste: true,
                  formatOnType: true
                });
                window.editor.onDidChangeModelContent(function(){
                  notifyChange(window.editor.getValue());
                });
                notifyReady();
              } catch(e) { notifyError(e); }
            });
          </script>
        </head>
        <body>
          <div id="container">
            <div id="editor"></div>
          </div>
        </body>
        </html>
        """
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

// MARK: - Fallback Editor (if Monaco fails)
struct FallbackCodeEditor: View {
    @Binding var code: String
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Monaco Editor (Fallback)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            TextEditor(text: $code)
                .font(.system(.body, design: .monospaced))
                .padding(8)
        }
    }
}

// MARK: - WKWebView wrapper for the Monaco HTML
struct WebViewHTML: NSViewRepresentable {
    var html: String
    var savedCode: String
    var language: String
    var onCodeChange: (String) -> Void

    func makeCoordinator() -> Coord { Coord(onCodeChange: onCodeChange, initialCode: savedCode) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.applicationNameForUserAgent = "Prism/1.0"

        // Message handlers for two-way bridge
        config.userContentController.add(context.coordinator, name: "codeChanged")
        config.userContentController.add(context.coordinator, name: "editorError")
        config.userContentController.add(context.coordinator, name: "editorReady")

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.customUserAgent = "Prism/1.0"
        web.setAccessibilityLabel("Code Editor")
        web.setAccessibilityRole(.group)
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        // Only load once to avoid clearing the session on each SwiftUI refresh.
        if view.url == nil && view.backForwardList.currentItem == nil {
            view.loadHTMLString(html, baseURL: URL(string: "https://cdn.jsdelivr.net"))
        }
    }

    final class Coord: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onCodeChange: (String) -> Void
        let initialCode: String

        init(onCodeChange: @escaping (String) -> Void, initialCode: String) {
            self.onCodeChange = onCodeChange
            self.initialCode = initialCode
        }

        deinit {
            // NOTE: NSViewRepresentable will create a fresh configuration on re-render.
            // If you ever reuse the same WKWebView, ensure you remove handlers here.
        }

        // Bridge from JS → Swift
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "codeChanged":
                if let text = message.body as? String { onCodeChange(text) }
            case "editorError":
                if let err = message.body as? String { print("Monaco Editor Error: \(err)") }
            case "editorReady":
                LoadingStateManager.shared.stopMonacoLoading()
            default:
                break
            }
        }

        // Modern JS prefs (per navigation action)
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            preferences.allowsContentJavaScript = true
            decisionHandler(.allow, preferences)
        }

        // Post-load: ensure initial content is set (in case loader defaulted)
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Sync editor content with Swift state (safe escaping)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let escaped = self.initialCode
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "'", with: "\\'")
                let js = """
                if (window.editor) {
                    window.editor.setValue('\(escaped)');
                } else {
                    window._code = '\(escaped)';
                }
                """
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        // Resilient error handling: show a minimal fallback HTML
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showMinimalErrorPage(in: webView, error: error)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showMinimalErrorPage(in: webView, error: error)
        }

        private func showMinimalErrorPage(in webView: WKWebView, error: Error) {
            let body = """
            <html><body>
              <h1>Editor Loading Failed</h1>
              <p>\(error.localizedDescription)</p>
              <p>If you are offline or the CDN is blocked, Prism will switch to a local editor.</p>
            </body></html>
            """
            webView.loadHTMLString(body, baseURL: nil)
        }
    }
}

// MARK: - File Manager (Open/New/Delete)
struct FileManagerView: View {
    @Binding var selectedLanguage: CodeLang
    @Binding var savedCode: String
    @Binding var currentFileName: String
    @Environment(\.dismiss) private var dismiss

    @State private var files: [URL] = []
    @State private var selectedFile: URL?

    var body: some View {
        VStack {
            HStack {
                Text("File Manager").font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()

            HStack {
                // File list
                VStack(alignment: .leading) {
                    Text("Recent Files")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    List(files, id: \.self, selection: $selectedFile) { file in
                        HStack {
                            Image(systemName: "doc.text")
                            Text(file.lastPathComponent)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            loadFile(file)
                        }
                    }
                }
                .frame(width: 220)

                Divider()

                // Actions
                VStack(spacing: 8) {
                    Button("Open File…") { openFile() }
                    Button("New File") { newFile() }
                    Button("Delete Selected") { deleteFile() }
                        .disabled(selectedFile == nil)
                }
                .padding()
            }
        }
        .frame(width: 520, height: 420)
        .onAppear { loadRecentFiles() }
    }

    private func codeFilesDirectory() -> URL {
        let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = doc.appendingPathComponent("Prism/CodeFiles")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadRecentFiles() {
        let dir = codeFilesDirectory()
        files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
            ?.filter { !$0.hasDirectoryPath }
            ?? []
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                loadFile(url)
            }
        }
    }

    private func loadFile(_ url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            savedCode = content
            currentFileName = url.lastPathComponent

            let ext = url.pathExtension.lowercased()
            if let lang = CodeLang.allCases.first(where: { $0.fileExtension == ext }) {
                selectedLanguage = lang
            }
            dismiss()
        } catch {
            print("Error loading file: \(error)")
        }
    }

    private func newFile() {
        savedCode = ""
        currentFileName = "untitled.\(selectedLanguage.fileExtension)"
        dismiss()
    }

    private func deleteFile() {
        guard let file = selectedFile else { return }
        do {
            try FileManager.default.removeItem(at: file)
            loadRecentFiles()
        } catch {
            print("Error deleting file: \(error)")
        }
    }
}

// MARK: - Export Options
struct ExportOptionsView: View {
    let code: String
    let language: CodeLang
    let fileName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Export Code").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                Button("Export to VSCode Project") { exportToVSCode() }
                Button("Export to Vim Configuration") { exportToVim() }
                Button("Export to Emacs Configuration") { exportToEmacs() }
                Button("Export to JetBrains Project") { exportToJetBrains() }
                Button("Export as Standalone File") { exportAsFile() }
            }
            HStack {
                Button("Close") { dismiss() }
                Spacer()
            }
        }
        .padding()
        .frame(width: 420, height: 320)
    }

    // VSCode
    private func exportToVSCode() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select VSCode Project Folder"
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                createVSCodeProject(at: url)
            }
        }
    }

    private func createVSCodeProject(at url: URL) {
        let projectName = fileName.components(separatedBy: ".").first ?? "prism-project"
        let projectPath = url.appendingPathComponent(projectName)

        do {
            try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
            // source file
            let sourceFile = projectPath.appendingPathComponent(fileName)
            try code.write(to: sourceFile, atomically: true, encoding: .utf8)

            // .vscode/settings.json
            let settingsPath = projectPath.appendingPathComponent(".vscode")
            try FileManager.default.createDirectory(at: settingsPath, withIntermediateDirectories: true)
            let settings = """
            {
              "files.associations": {
                "*.\(language.fileExtension)": "\(monacoLanguage(language))"
              }
            }
            """
            try settings.write(to: settingsPath.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
            dismiss()
        } catch {
            print("Error creating VSCode project: \(error)")
        }
    }

    // Vim
    private func exportToVim() {
        let vimConfig = """
        " Prism Export - \(fileName)
        set syntax=\(vimSyntax())
        set number
        set autoindent
        set smartindent

        " Code content:
        \(code)
        """
        saveExportFile(vimConfig, fileExtension: "vim")
    }

    // Emacs
    private func exportToEmacs() {
        let emacsConfig = """
        ;; Prism Export - \(fileName)
        ;; -*- mode: \(emacsMode()) -*-

        \(code)
        """
        saveExportFile(emacsConfig, fileExtension: "el")
    }

    // JetBrains (placeholder project)
    private func exportToJetBrains() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select JetBrains Project Folder"
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                createJetBrainsProject(at: url)
            }
        }
    }

    private func createJetBrainsProject(at url: URL) {
        let projectName = fileName.components(separatedBy: ".").first ?? "prism-project"
        let projectPath = url.appendingPathComponent(projectName)

        do {
            try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)
            // source file
            let sourceFile = projectPath.appendingPathComponent(fileName)
            try code.write(to: sourceFile, atomically: true, encoding: .utf8)
            // minimal .idea dir scaffold
            let ideaPath = projectPath.appendingPathComponent(".idea")
            try FileManager.default.createDirectory(at: ideaPath, withIntermediateDirectories: true)
            dismiss()
        } catch {
            print("Error creating JetBrains project: \(error)")
        }
    }

    // Standalone
    private func exportAsFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: language.fileExtension) ?? .plainText]
        panel.nameFieldStringValue = fileName
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                do {
                    try code.write(to: url, atomically: true, encoding: .utf8)
                    dismiss()
                } catch {
                    print("Error saving file: \(error)")
                }
            }
        }
    }

    private func saveExportFile(_ content: String, fileExtension: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .plainText]
        panel.nameFieldStringValue = "\(fileName).\(fileExtension)"
        panel.begin { resp in
            if resp == .OK, let url = panel.url {
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    dismiss()
                } catch {
                    print("Error saving export file: \(error)")
                }
            }
        }
    }

    // Helpers for modes/languages in export configs
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

    private func vimSyntax() -> String {
        switch language {
        case .python: return "python"
        case .ruby: return "ruby"
        case .node, .javascript: return "javascript"
        case .swift: return "swift"
        case .bash: return "sh"
        case .go: return "go"
        case .c: return "c"
        case .cpp: return "cpp"
        case .rust: return "rust"
        case .java: return "java"
        case .sql: return "sql"
        }
    }

    private func emacsMode() -> String {
        switch language {
        case .python: return "python"
        case .ruby: return "ruby"
        case .node, .javascript: return "javascript"
        case .swift: return "swift"
        case .bash: return "sh"
        case .go: return "go"
        case .c: return "c"
        case .cpp: return "c++"
        case .rust: return "rust"
        case .java: return "java"
        case .sql: return "sql"
        }
    }
}

// MARK: - Minimal Shell Runner
// Writes the code to a temp file (inside the sandbox), then runs an interpreter/command.
// We keep a modest set of supported languages to avoid toolchain complexity.
enum Shell {
    static func run(language: CodeLang, code: String) -> String {
        switch language {
        case .python:
            return runProcess(cmd: "/usr/bin/env", args: ["python3", "-"], stdin: code)
        case .ruby:
            return runProcess(cmd: "/usr/bin/env", args: ["ruby", "-e", code], stdin: nil)
        case .node, .javascript:
            return runProcess(cmd: "/usr/bin/env", args: ["node", "-e", code], stdin: nil)
        case .swift:
            // Swift REPL via stdin is fragile; write to a temp file and run `swift <file>`
            return runViaTempFile(ext: "swift", languageCommand: "swift", args: [], code: code)
        case .bash:
            return runProcess(cmd: "/usr/bin/env", args: ["bash", "-c", code], stdin: nil)

        // For compiled languages / heavier toolchains, we show a clear message:
        case .go, .c, .cpp, .rust, .java, .sql:
            return "Runner: \(language.rawValue) execution is not enabled in Prism’s sandbox yet.\n" +
                   "Tip: Use Export → VSCode/JetBrains, or Save and run externally."
        }
    }

    private static func runViaTempFile(ext: String, languageCommand: String, args: [String], code: String) -> String {
        let tmp = FileManager.default.temporaryDirectory
        let file = tmp.appendingPathComponent("prism-\(UUID().uuidString).\(ext)")
        do {
            try code.write(to: file, atomically: true, encoding: .utf8)
            var allArgs = [file.path]
            allArgs.insert(contentsOf: args, at: 0)
            return runProcess(cmd: "/usr/bin/env", args: [languageCommand] + allArgs, stdin: nil)
        } catch {
            return "Error writing temp file: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private static func runProcess(cmd: String, args: [String], stdin: String?) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: cmd)
        task.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        if let text = stdin {
            let inPipe = Pipe()
            task.standardInput = inPipe
            do {
                try task.run()
            } catch {
                return "Failed to start process: \(error.localizedDescription)"
            }
            inPipe.fileHandleForWriting.write(Data(text.utf8))
            inPipe.fileHandleForWriting.closeFile()
        } else {
            do {
                try task.run()
            } catch {
                return "Failed to start process: \(error.localizedDescription)"
            }
        }

        task.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return out + (out.isEmpty ? "" : "\n") + "stderr:\n" + err
        }
        return out
    }
}
