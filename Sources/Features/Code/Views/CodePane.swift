import SwiftUI
import WebKit
import UniformTypeIdentifiers
import Combine   // <- add this

// MARK: - CodePane

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

struct ScratchRunner: View {
    @State private var language: CodeLang = .python
    @State private var code: String = ""
    @State private var output: String = ""
    @State private var isRunning = false

    private var defaultCode: String {
        switch language {
        case .python: return "# Example:\nprint('hello from Prism!')"
        case .ruby:   return "# Example:\nputs 'hello from Prism!'"
        case .node, .javascript: return "// Example:\nconsole.log('hello from Prism!');"
        case .swift:  return "// Example:\nprint(\"hello from Prism!\")"
        case .bash:   return "# Example:\necho 'hello from Prism!'"
        case .go:     return "// Toolchain not enabled in this demo."
        case .c:      return "// Toolchain not enabled in this demo."
        case .cpp:    return "// Toolchain not enabled in this demo."
        case .rust:   return "// Toolchain not enabled in this demo."
        case .java:   return "// Toolchain not enabled in this demo."
        case .sql:    return "-- Requires DB; demo prints query."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
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

            TextEditor(text: $code)
                .font(.system(.body, design: .monospaced))
                .padding(8)

            Divider()

            ScrollView {
                Text(output)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { if code.isEmpty { code = defaultCode } }
        .onChange(of: language) { code = defaultCode }
    }

    private func run() {
        isRunning = true
        output = ""
        LoadingStateManager.shared.startLoading(.general, message: "Running \(language.rawValue) code...")
        let lang = language
        let src = code
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Shell.runCode(lang.rawValue, code: src)
            DispatchQueue.main.async {
                self.output = result
                self.isRunning = false
                LoadingStateManager.shared.stopLoading(.general)
            }
        }
    }
}

// MARK: - Monaco editor

enum CodeLang: String, CaseIterable {
    case python = "Python", ruby = "Ruby", node = "Node.js", swift = "Swift",
         javascript = "JavaScript", bash = "Bash", go = "Go", c = "C",
         cpp = "C++", rust = "Rust", java = "Java", sql = "SQL"

    var fileExtension: String {
        switch self {
        case .python: return "py"
        case .ruby:   return "rb"
        case .node, .javascript: return "js"
        case .swift:  return "swift"
        case .bash:   return "sh"
        case .go:     return "go"
        case .c:      return "c"
        case .cpp:    return "cpp"
        case .rust:   return "rs"
        case .java:   return "java"
        case .sql:    return "sql"
        }
    }
}

struct MonacoWebEditor: View {
    @AppStorage("monacoCode") private var savedCode: String = ""
    @State private var useFallback = false
    @State private var selectedLanguage: CodeLang = .python
    @State private var output: String = ""
    @State private var isRunning = false
    @State private var showFileManager = false
    @State private var currentFileName = "untitled.py"
    @State private var showExportOptions = false

    private func html(_ initial: String) -> String {
        let language = monacoLanguage(selectedLanguage)
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body,#container{height:100%;margin:0}#container{display:flex;flex-direction:column}#editor{flex:1;}</style>
        <script src="https://cdn.jsdelivr.net/npm/monaco-editor@0.52.0/min/vs/loader.js"></script>
        <script>
        require.config({ paths: { 'vs': 'https://cdn.jsdelivr.net/npm/monaco-editor@0.52.0/min/vs' } });
        window._code = `\(initial.replacingOccurrences(of: "`", with: "\\`"))`;
        window._language = '\(language)';
        require(['vs/editor/editor.main'], function(){
          window.editor = monaco.editor.create(document.getElementById('editor'), {
            value: window._code, language: window._language, automaticLayout: true,
            theme: 'vs-dark', minimap: { enabled: true }, wordWrap: 'on', lineNumbers: 'on',
            folding: true, bracketPairColorization: { enabled: true }, formatOnPaste: true, formatOnType: true
          });
          window.editor.onDidChangeModelContent(function(){
            try { window.webkit.messageHandlers.codeChanged.postMessage(window.editor.getValue()); } catch(e) { }
          });
        });
        </script></head><body><div id="container"><div id="editor"></div></div></body></html>
        """
    }

    private func monacoLanguage(_ lang: CodeLang) -> String {
        switch lang {
        case .python: return "python"
        case .ruby:   return "ruby"
        case .node, .javascript: return "javascript"
        case .swift:  return "swift"
        case .bash:   return "shell"
        case .go:     return "go"
        case .c:      return "c"
        case .cpp:    return "cpp"
        case .rust:   return "rust"
        case .java:   return "java"
        case .sql:    return "sql"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(CodeLang.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 140)

                Button(isRunning ? "Running…" : "Run") { executeCode() }.disabled(isRunning)
                Button("Save") { saveFile() }
                Button("Load") { showFileManager = true }
                Button("Export") { showExportOptions = true }

                Spacer()
                Text(currentFileName).font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Editor + Output
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if useFallback {
                        FallbackCodeEditor(code: $savedCode)
                    } else {
                        WebViewHTML(html: html(savedCode), savedCode: savedCode) { newCode in
                            savedCode = newCode
                        }
                        .onAppear {
                            LoadingStateManager.shared.startMonacoLoading("Initializing Monaco editor...")
                            // If CDN blocked/offline, flip to fallback after a grace period.
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

                // Output
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Output").font(.headline).padding(.horizontal, 8).padding(.vertical, 4)
                        Spacer()
                        Button("Clear") { output = "" }.font(.caption).padding(.horizontal, 8)
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
                .frame(width: 300)
            }
        }
        .sheet(isPresented: $showFileManager) {
            FileManagerView(selectedLanguage: $selectedLanguage, savedCode: $savedCode, currentFileName: $currentFileName)
        }
        .sheet(isPresented: $showExportOptions) {
            ExportOptionsView(code: savedCode, language: selectedLanguage, fileName: currentFileName)
        }
        .onChange(of: selectedLanguage) {
            // Optional: inject JS to switch Monaco language without reload.
        }
    }

    private func executeCode() {
        isRunning = true
        output = ""
        LoadingStateManager.shared.startLoading(.general, message: "Running \(selectedLanguage.rawValue) code...")
        let lang = selectedLanguage
        let src = savedCode
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Shell.runCode(lang.rawValue, code: src)
            DispatchQueue.main.async {
                self.output = result
                self.isRunning = false
                LoadingStateManager.shared.stopLoading(.general)
            }
        }
    }

    private func saveFile() {
        LoadingStateManager.shared.startFileOperation("Saving file...")
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: selectedLanguage.fileExtension) ?? .plainText]
        if !currentFileName.lowercased().hasSuffix(".\(selectedLanguage.fileExtension)") {
            currentFileName = "untitled.\(selectedLanguage.fileExtension)"
        }
        panel.nameFieldStringValue = currentFileName
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try savedCode.write(to: url, atomically: true, encoding: .utf8)
                    currentFileName = url.lastPathComponent
                } catch {
                    output = "Error saving file: \(error.localizedDescription)"
                }
            }
            LoadingStateManager.shared.stopFileOperation()
        }
    }
}

// MARK: - Fallback editor

struct FallbackCodeEditor: View {
    @Binding var code: String
    var body: some View {
        VStack(spacing: 4) {
            Text("Monaco Editor (Fallback Mode)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $code)
                .font(.system(.body, design: .monospaced))
                .padding(8)
        }
    }
}

// MARK: - WebView wrapper (macOS)

struct WebViewHTML: NSViewRepresentable {
    var html: String
    var savedCode: String
    var onCodeChange: (String) -> Void

    func makeCoordinator() -> Coord { Coord(onCodeChange: onCodeChange, savedCode: savedCode) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.applicationNameForUserAgent = "Prism/1.0"
        config.userContentController.add(context.coordinator, name: "codeChanged")
        config.userContentController.add(context.coordinator, name: "editorError")
        config.userContentController.add(context.coordinator, name: "editorReady")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Prism/1.0"

        // Accessibility hints (macOS)
        webView.setAccessibilityLabel("Code Editor")
        webView.setAccessibilityRole(.group)

        // Transparent background
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if view.url == nil {
            view.loadHTMLString(html, baseURL: URL(string: "https://cdn.jsdelivr.net"))
        }
    }

    final class Coord: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onCodeChange: (String) -> Void
        let savedCode: String

        init(onCodeChange: @escaping (String) -> Void, savedCode: String) {
            self.onCodeChange = onCodeChange
            self.savedCode = savedCode
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "codeChanged":
                if let text = message.body as? String { onCodeChange(text) }
            case "editorError":
                if let error = message.body as? String { print("Monaco Editor Error: \(error)") }
            case "editorReady":
                LoadingStateManager.shared.stopMonacoLoading()
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // seed the editor with saved code
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let escaped = self.savedCode
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "'", with: "\\'")
                let js = "if (window.editor) { window.editor.setValue('\(escaped)'); } else { window._code = '\(escaped)'; }"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Monaco WebView navigation failed: \(error.localizedDescription)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                webView.loadHTMLString("<html><body><h1>Editor Loading Failed</h1><p>Please try refreshing the editor.</p></body></html>", baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("Monaco WebView provisional navigation failed: \(error.localizedDescription)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                webView.loadHTMLString("<html><body><h1>Editor Loading Failed</h1><p>Please try refreshing the editor.</p></body></html>", baseURL: nil)
            }
        }

        // macOS 11+; okay to keep. If your target < 11, drop the `preferences:` variant.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            preferences.allowsContentJavaScript = true
            decisionHandler(.allow, preferences)
        }
    }
}

// MARK: - Lightweight runtime stubs (remove if you already have these)

// MARK: - Lightweight runtime stubs for this view only
// If you already have real implementations elsewhere, this won't collide.

@MainActor
final class CodeLoadingStateManager: ObservableObject {
    enum Channel { case general }
    static let shared = CodeLoadingStateManager()

    func startLoading(_ channel: Channel, message: String) {}
    func stopLoading(_ channel: Channel) {}
    func startFileOperation(_ message: String) {}
    func stopFileOperation() {}
    func startMonacoLoading(_ message: String) {}
    func stopMonacoLoading() {}
}

enum CodeShell {
    static func runCode(_ language: String, code: String) -> String {
        let cmd: String
        let args: [String]
        switch language.lowercased() {
        case "python", "python3": cmd = "/usr/bin/env"; args = ["python3", "-c", code]
        case "ruby":              cmd = "/usr/bin/env"; args = ["ruby", "-e", code]
        case "node.js", "javascript", "node":
            cmd = "/usr/bin/env"; args = ["node", "-e", code]
        case "bash", "shell":
            cmd = "/bin/bash";    args = ["-lc", code]
        case "swift":
            return runProcess("/usr/bin/env", ["swift", "-"], stdin: code)
        default:
            return "Execution for \(language) is not enabled in this build."
        }
        return runProcess(cmd, args, stdin: nil)
    }

    private static func runProcess(_ launchPath: String, _ arguments: [String], stdin: String?) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = arguments

        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        do { try p.run() } catch { return "Failed to run: \(error.localizedDescription)" }

        if let s = stdin {
            let inPipe = Pipe()
            p.standardInput = inPipe
            inPipe.fileHandleForWriting.write(Data(s.utf8))
            try? inPipe.fileHandleForWriting.close()
        }

        p.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return err.isEmpty ? out : (out.isEmpty ? err : out + "\n" + err)
    }
}

// Placeholder views for sheets. Replace with your real implementations.
struct FileManagerView: View {
    @Binding var selectedLanguage: CodeLang
    @Binding var savedCode: String
    @Binding var currentFileName: String
    var body: some View {
        VStack(spacing: 12) {
            Text("File Manager Placeholder")
            Button("Close") { NSApp.keyWindow?.endSheet(NSWindow()) }
        }.frame(width: 320, height: 160)
    }
}

struct ExportOptionsView: View {
    var code: String
    var language: CodeLang
    var fileName: String
    var body: some View {
        VStack(spacing: 12) {
            Text("Export Options Placeholder")
            Text("Language: \(language.rawValue)")
            Button("Close") { NSApp.keyWindow?.endSheet(NSWindow()) }
        }.frame(width: 320, height: 160)
    }
}
