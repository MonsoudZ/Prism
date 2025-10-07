//
//  WebPane.swift
//  Prism
//
//  A lightweight, embedded reference browser for side-by-side docs.
//  - URL bar with tolerant parsing (adds https://; search fallback)
//  - Back/Forward history with correct truncation
//  - Bookmarks persisted via PersistenceService
//  - Loading spinner integration via LoadingStateManager
//  - macOS-native accessibility + keyboard affordances
//

import SwiftUI
import WebKit
import AppKit
import Foundation

// MARK: - WebPane (SwiftUI shell around WKWebView)

struct WebPane: View {
    // ---------- State ----------
    @State private var urlString: String = "https://developer.apple.com/documentation/pdfkit"
    @State private var currentURL: URL?
    @State private var history: [URL] = []
    @State private var historyIndex: Int = -1
    @State private var bookmarks: [URL] = []

    // Persist the last visited URL across launches
    @AppStorage("prism.web.lastURL") private var lastURLString: String = ""

    // Keys for PersistenceService (atomic JSON under your app data dir)
    private let bookmarksKey = "Prism.Web.Bookmarks.v1"

    // ---------- Derived ----------
    private var canGoBack: Bool { historyIndex > 0 }
    private var canGoForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            HStack(spacing: 8) {
                Button {
                    goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(!canGoBack)
                .help("Back")

                Button {
                    goForward()
                } label: {
                    Label("Forward", systemImage: "chevron.right")
                }
                .disabled(!canGoForward)
                .help("Forward")

                Divider()

                HStack(spacing: 8) {
                    TextField("Enter URL or search…", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { loadFromBar() }
                        .help("Type a URL (e.g., apple.com/pdfkit) or a search query")

                    Button {
                        loadFromBar()
                    } label: {
                        Label("Go", systemImage: "arrow.turn.down.right")
                    }
                    .keyboardShortcut(.return, modifiers: []) // ⏎ triggers Go
                    .help("Load")
                }
                .frame(minWidth: 380)

                Divider()

                // Bookmarks menu
                Menu {
                    if bookmarks.isEmpty {
                        Text("No bookmarks yet")
                    } else {
                        ForEach(bookmarks, id: \.self) { u in
                            Button(u.displayTitle) { openURL(u, record: true) }
                        }
                        Divider()
                        Button("Export Bookmarks…") { exportBookmarks() }
                    }
                    Divider()
                    Button(isBookmarked(currentURL) ? "Remove Bookmark" : "Add Bookmark") {
                        toggleBookmark()
                    }
                    .disabled(currentURL == nil)
                } label: {
                    Label("Bookmarks", systemImage: "book")
                }
                .help("Bookmarks")

                // History menu
                Menu {
                    if history.isEmpty {
                        Text("No history yet")
                    } else {
                        ForEach(history.indices, id: \.self) { idx in
                            let u = history[idx]
                            Button(u.displayTitle) { jumpToHistoryIndex(idx) }
                        }
                        Divider()
                        Button("Clear History") { clearHistory() }
                    }
                } label: {
                    Label("History", systemImage: "clock")
                }
                .help("History")

                Spacer()

                Button {
                    if let u = currentURL { NSWorkspace.shared.open(u) }
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
                .disabled(currentURL == nil)
                .help("Open in default browser")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // The actual web view
            WebView(url: currentURL) { newURL in
                onNavigated(newURL)
            }
        }
        .onAppear {
            loadBookmarks()
            // Restore last URL if present; otherwise use default in urlString
            if let restored = URL(string: lastURLString), !lastURLString.isEmpty {
                openURL(restored, record: true)
                urlString = restored.absoluteString
            } else if let u = URL(string: urlString) {
                openURL(u, record: true)
            }
        }
    }

    // MARK: - Actions

    /// Try to interpret address bar text as a URL; if not, fall back to a search query.
    private func loadFromBar() {
        let input = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        LoadingStateManager.shared.startWebLoading("Loading webpage…")

        if let url = normalizeURL(from: input) {
            openURL(url, record: true)
        } else if let searchURL = makeSearchURL(query: input) {
            openURL(searchURL, record: true)
        }
    }

    /// Open a URL and optionally record it in history.
    private func openURL(_ url: URL, record: Bool = false) {
        currentURL = url
        urlString = url.absoluteString
        lastURLString = url.absoluteString

        if record { appendHistory(url) }
    }

    /// Called by WebView when navigation finishes/changes.
    private func onNavigated(_ url: URL?) {
        LoadingStateManager.shared.stopWebLoading()
        guard let u = url else { return }
        // Avoid double pushes if the webview reports the same URL repeatedly
        if currentURL?.absoluteString != u.absoluteString {
            openURL(u, record: true)
        }
    }

    /// Append to history, truncating any “forward” entries if we branched.
    private func appendHistory(_ url: URL) {
        if historyIndex >= 0 && historyIndex < history.count - 1 {
            history = Array(history.prefix(historyIndex + 1))
        }
        if history.last != url {
            history.append(url)
            historyIndex = history.count - 1
        }
    }

    private func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        let u = history[historyIndex]
        currentURL = u
        urlString = u.absoluteString
        lastURLString = u.absoluteString
    }

    private func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        let u = history[historyIndex]
        currentURL = u
        urlString = u.absoluteString
        lastURLString = u.absoluteString
    }

    private func jumpToHistoryIndex(_ idx: Int) {
        guard history.indices.contains(idx) else { return }
        historyIndex = idx
        let u = history[idx]
        currentURL = u
        urlString = u.absoluteString
        lastURLString = u.absoluteString
    }

    private func clearHistory() {
        history.removeAll()
        historyIndex = -1
    }

    private func toggleBookmark() {
        guard let u = currentURL else { return }
        if let i = bookmarks.firstIndex(of: u) {
            bookmarks.remove(at: i)
        } else {
            bookmarks.removeAll { $0.absoluteString == u.absoluteString }
            bookmarks.insert(u, at: 0)
        }
        saveBookmarks()
    }

    private func isBookmarked(_ url: URL?) -> Bool {
        guard let u = url else { return false }
        return bookmarks.contains(where: { $0.absoluteString == u.absoluteString })
    }

    private func loadBookmarks() {
        if let arr: [URL] = PersistenceService.loadCodable([URL].self, forKey: bookmarksKey) {
            bookmarks = arr
        }
    }

    private func saveBookmarks() {
        PersistenceService.saveCodable(bookmarks, forKey: bookmarksKey)
    }

    private func exportBookmarks() {
        // Simple export to a .txt list of URLs in /tmp, could be extended to HTML bookmarks file
        let lines = bookmarks.map { $0.absoluteString }.joined(separator: "\n")
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("Prism_Bookmarks_\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try lines.write(to: outURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([outURL])
        } catch {
            // Non-fatal; just ignore for now or route to your EnhancedToastCenter
            print("Failed to export bookmarks: \(error.localizedDescription)")
        }
    }

    // MARK: - URL Helpers

    /// Convert loose user input into a valid https URL when possible.
    /// - Adds https:// if scheme missing
    /// - If input has spaces or no dots, we consider it a search
    private func normalizeURL(from input: String) -> URL? {
        // If it already parses as a URL with scheme, use it
        if let direct = URL(string: input), direct.scheme != nil {
            return direct
        }

        // If it looks like a host/path (no spaces) add https://
        if !input.contains(" ") {
            // Add https if missing and try again
            if let withScheme = URL(string: "https://" + input) {
                // Validate host existence
                if withScheme.host != nil {
                    return withScheme
                }
                // Try as a path under https:// if user typed like "apple.com/docs/pdfkit"
                if let url = URL(string: "https://" + input.addingPercentEncoding(withAllowedCharacters: .urlPathAllowedCharacters) ) {
                    return url
                }
            }
        }
        return nil
    }

    /// If input isn’t a URL, search with DuckDuckGo (privacy-friendly).
    private func makeSearchURL(query: String) -> URL? {
        var comps = URLComponents(string: "https://duckduckgo.com/")!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        return comps.url
    }
}

// MARK: - WebView (NSViewRepresentable WKWebView wrapper)

struct WebView: NSViewRepresentable {
    var url: URL?
    var onNavigated: (URL?) -> Void

    func makeCoordinator() -> Coord { Coord(onNavigated: onNavigated) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Prefer default store (cookies/cache) so sessions persist
        config.websiteDataStore = WKWebsiteDataStore.default()

        // Keep popups within the webview
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        // Identify as Prism (safe custom UA suffix)
        config.applicationNameForUserAgent = "Prism/1.0"

        let v = WKWebView(frame: .zero, configuration: config)
        v.navigationDelegate = context.coordinator
        v.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 Prism/1.0"

        // macOS accessibility
        v.setAccessibilityLabel("Web Browser")
        v.setAccessibilityRole(.group)

        return v
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard let u = url else { return }
        if view.url != u {
            let request = URLRequest(url: u)
            view.load(request)
        }
    }

    final class Coord: NSObject, WKNavigationDelegate {
        let onNavigated: (URL?) -> Void
        init(onNavigated: @escaping (URL?) -> Void) { self.onNavigated = onNavigated }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            LoadingStateManager.shared.stopWebLoading()
            onNavigated(webView.url)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            LoadingStateManager.shared.stopWebLoading()
            print("WebView navigation failed: \(error.localizedDescription)")
            onNavigated(webView.url) // still report where we are
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            LoadingStateManager.shared.stopWebLoading()
            print("WebView provisional navigation failed: \(error.localizedDescription)")
            onNavigated(webView.url)
        }

        // Allow all navigations; tweak if you want to filter schemes
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        // Modern per-navigation JS preference hook
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            preferences.allowsContentJavaScript = true
            decisionHandler(.allow, preferences)
        }
    }
}

// MARK: - Small helpers

private extension URL {
    /// Human-readable title for menus (host + maybe path)
    var displayTitle: String {
        if let host = self.host {
            if path.isEmpty || path == "/" { return host }
            return host + path
        }
        return absoluteString
    }
}

private extension CharacterSet {
    /// Allow typical path characters when rebuilding URLs
    static let urlPathAllowedCharacters: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.formUnion(.urlQueryAllowed)
        return set
    }()
}
