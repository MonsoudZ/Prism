//
//  WebViewModel.swift
//  Prism
//
//  A lightweight view model for the in-app reference browser.
//  - URL normalization (adds https://, falls back to search)
//  - History with proper branch truncation
//  - Bookmarks persisted via PersistenceService
//  - Remembers last visited URL via @AppStorage bridge (exposed API)
//  - Integrates with LoadingStateManager for spinner feedback
//
//  Created by Monsoud Zanaty on 10/4/25.
//

import Foundation
import SwiftUI
import AppKit

@MainActor
final class WebViewModel: ObservableObject {

    // MARK: - Published, UI-observable state

    /// The current URL shown by the WKWebView.
    @Published var currentURL: URL?

    /// The user-facing address bar text. Keep in sync with currentURL.
    @Published var addressText: String = "https://developer.apple.com/documentation/pdfkit"

    /// Linear history of visited URLs.
    @Published private(set) var history: [URL] = []

    /// Current index into `history` (-1 means no entries yet).
    @Published private(set) var historyIndex: Int = -1

    /// Saved bookmarks.
    @Published private(set) var bookmarks: [URL] = []

    // MARK: - Persistence keys

    /// Where we store bookmarks (atomic JSON via PersistenceService).
    private let bookmarksKey = "Prism.Web.Bookmarks.v1"

    /// Remember last URL across launches.
    @AppStorage("prism.web.lastURL") var lastURLString: String = ""

    // MARK: - Derived convenience

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }

    // MARK: - Lifecycle

    init() {
        loadBookmarks()
        restoreLastURLIfAvailable()
    }

    // MARK: - Public API used by the view

    /// Called when the user presses return / Go in the address bar.
    func loadFromAddressBar() {
        let input = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        LoadingStateManager.shared.startWebLoading("Loading webpage…")

        if let url = normalizeURL(from: input) {
            openURL(url, recordInHistory: true)
        } else if let searchURL = makeSearchURL(query: input) {
            openURL(searchURL, recordInHistory: true)
        } else {
            LoadingStateManager.shared.stopWebLoading()
        }
    }

    /// Open an absolute URL (e.g., from menus or restored state).
    func openURL(_ url: URL, recordInHistory: Bool) {
        currentURL = url
        addressText = url.absoluteString
        lastURLString = url.absoluteString

        if recordInHistory { appendHistory(url) }
    }

    /// The web view calls this upon navigation completion.
    func onWebViewNavigated(to url: URL?) {
        LoadingStateManager.shared.stopWebLoading()
        guard let u = url else { return }

        // Avoid noisy duplicates
        if currentURL?.absoluteString != u.absoluteString {
            openURL(u, recordInHistory: true)
        }
    }

    // MARK: - History controls

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        let u = history[historyIndex]
        assignURLWithoutRewritingHistory(u)
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        let u = history[historyIndex]
        assignURLWithoutRewritingHistory(u)
    }

    func jumpToHistoryIndex(_ idx: Int) {
        guard history.indices.contains(idx) else { return }
        historyIndex = idx
        let u = history[idx]
        assignURLWithoutRewritingHistory(u)
    }

    func clearHistory() {
        history.removeAll()
        historyIndex = -1
    }

    // MARK: - Bookmarks

    func toggleBookmark() {
        guard let u = currentURL else { return }
        if let i = bookmarks.firstIndex(where: { $0.absoluteString == u.absoluteString }) {
            bookmarks.remove(at: i)
        } else {
            // de-dup by string
            bookmarks.removeAll { $0.absoluteString == u.absoluteString }
            bookmarks.insert(u, at: 0)
        }
        saveBookmarks()
    }

    func isBookmarked(_ url: URL?) -> Bool {
        guard let u = url else { return false }
        return bookmarks.contains(where: { $0.absoluteString == u.absoluteString })
    }

    func exportBookmarks() {
        // Minimal export to a txt for convenience. You can extend to HTML/Netscape format.
        let lines = bookmarks.map { $0.absoluteString }.joined(separator: "\n")
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Prism_Bookmarks_\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try lines.write(to: outURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([outURL])
        } catch {
            // Route to a toast if you want; non-fatal here
            print("Failed to export bookmarks: \(error.localizedDescription)")
        }
    }

    // MARK: - Private helpers

    private func appendHistory(_ url: URL) {
        // If we navigated after going back, truncate forward history
        if historyIndex >= 0 && historyIndex < history.count - 1 {
            history = Array(history.prefix(historyIndex + 1))
        }
        if history.last != url {
            history.append(url)
            historyIndex = history.count - 1
        }
    }

    private func assignURLWithoutRewritingHistory(_ url: URL) {
        currentURL = url
        addressText = url.absoluteString
        lastURLString = url.absoluteString
    }

    private func loadBookmarks() {
        if let arr: [URL] = PersistenceService.loadCodable([URL].self, forKey: bookmarksKey) {
            bookmarks = arr
        }
    }

    private func saveBookmarks() {
        PersistenceService.saveCodable(bookmarks, forKey: bookmarksKey)
    }

    private func restoreLastURLIfAvailable() {
        if let restored = URL(string: lastURLString), !lastURLString.isEmpty {
            openURL(restored, recordInHistory: true)
        } else if let fallback = URL(string: addressText) {
            openURL(fallback, recordInHistory: true)
        }
    }

    // MARK: - URL construction

    /// Tolerant URL parser:
    /// - If input already has a scheme, we try it as-is
    /// - If it looks like a host/path (no spaces), we prefix https://
    /// - Otherwise we return nil (caller should try search)
    private func normalizeURL(from input: String) -> URL? {
        // Already a full URL with scheme
        if let direct = URL(string: input), direct.scheme != nil {
            return direct
        }

        // If it looks like a hostname/path and has no spaces, add https://
        if !input.contains(" ") {
            if let withScheme = URL(string: "https://" + input) {
                if withScheme.host != nil { return withScheme }
                // Try percent-encoding for pathy strings
                if let encoded = ("https://" + input).addingPercentEncoding(withAllowedCharacters: .urlPathAllowedCharacters),
                   let url = URL(string: encoded) {
                    return url
                }
            }
        }
        return nil
    }

    /// Builds a search URL if input isn't a valid URL.
    private func makeSearchURL(query: String) -> URL? {
        var comps = URLComponents(string: "https://duckduckgo.com/")!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        return comps.url
    }
}

// MARK: - CharacterSet helper for tolerant path encoding

private extension CharacterSet {
    static let urlPathAllowedCharacters: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.formUnion(.urlQueryAllowed)
        return set
    }()
}
