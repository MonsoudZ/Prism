//
//  PDFViewModel.swift
//  Prism
//
//  Created by Monsoud Zanaty on 10/5/25.
//
//  What this file does
//  -------------------
//  A lightweight, SwiftUI-friendly view model that owns PDF state for Prism:
//  • Loads a PDFDocument from disk (with simple validation).
//  • Tracks current page, reading progress, and “large-PDF” hints.
//  • Provides basic search with highlighted selections.
//  • Persists/recovers the last-read page per file.
//  • Manages simple per-PDF bookmarks.
//
//  Why we need it
//  --------------
//  PDFKit’s PDFView is AppKit and doesn’t manage app state (page index,
//  search state, etc.). This @MainActor ObservableObject centralizes that state
//  so SwiftUI views (like PDFViewRepresentable, toolbars, outline panes) can
//  bind to it predictably without importing heavier app-wide controllers.
//

import SwiftUI
import PDFKit
import Combine
import AppKit

@MainActor
final class PDFViewModel: ObservableObject {
    // MARK: - Published UI State
    
    /// Currently loaded document (nil if none).
    @Published var document: PDFDocument?
    
    /// The 0-based index of the visible page (bound to the PDFViewRepresentable).
    @Published var currentPageIndex: Int = 0 {
        didSet { persistLastPageIfNeeded() ; updateReadingProgress() }
    }
    
    /// Simple reading-progress ratio [0, 1].
    @Published private(set) var readingProgress: Double = 0.0
    
    /// Heuristic to turn on safer rendering defaults for big docs.
    @Published private(set) var isLargePDF: Bool = false
    
    /// URL for the currently-loaded PDF (original source file).
    @Published private(set) var currentURL: URL?
    
    // MARK: Search
    
    /// Current search query.
    @Published var searchQuery: String = ""
    /// All highlighted selections for the active query.
    @Published private(set) var searchResults: [PDFSelection] = []
    /// Index of the “active” selection inside `searchResults`.
    @Published var searchIndex: Int = 0
    /// Spinner flag for long-running searches.
    @Published var isSearching: Bool = false
    
    // MARK: Bookmarks (by page index, per PDF)
    @Published private(set) var bookmarks: Set<Int> = []
    
    // MARK: - Private
    
    private var cancellables = Set<AnyCancellable>()
    private let pagePersistKeyPrefix = "Prism.PageForURL."
    private let bookmarksKeyPrefix  = "Prism.BookmarksForURL."
    
    // MARK: - Lifecycle
    
    init() {
        // Keep progress up-to-date when document changes
        $document
            .sink { [weak self] _ in self?.updateReadingProgress() }
            .store(in: &cancellables)
    }
    
    // MARK: - Public API
    
    /// Load a PDF from disk with basic validation and large-PDF hints.
    func load(url: URL) {
        // If it’s the same document, do nothing.
        if currentURL == url { return }
        
        // Reset prior document state.
        clear()
        
        // Try to open.
        guard let doc = PDFDocument(url: url) else {
            NSSound.beep()
            return
        }
        guard doc.pageCount > 0 else {
            NSSound.beep()
            return
        }
        
        // Adopt.
        document = doc
        currentURL = url
        isLargePDF = doc.pageCount >= 500
        
        // Restore last page if available.
        if let saved = loadLastPage(for: url) {
            let clamped = min(max(0, saved), doc.pageCount - 1)
            currentPageIndex = clamped
        } else {
            currentPageIndex = 0
        }
        
        // Load bookmarks.
        bookmarks = loadBookmarks(for: url)
    }
    
    /// Unload the current PDF and reset state.
    func clear() {
        document = nil
        currentURL = nil
        isLargePDF = false
        currentPageIndex = 0
        searchQuery = ""
        searchResults.removeAll()
        searchIndex = 0
        isSearching = false
        bookmarks.removeAll()
    }
    
    /// Jump to a page, clamped to the document’s range.
    func goToPage(_ pageIndex: Int) {
        guard let doc = document else { return }
        let clamped = min(max(0, pageIndex), doc.pageCount - 1)
        currentPageIndex = clamped
    }
    
    // MARK: - Search
    
    /// Run a simple, synchronous PDFKit search with case-insensitive matching.
    /// For very large PDFs, consider throttling/debouncing calls from the UI.
    func performSearch(_ query: String) {
        guard let doc = document else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchQuery = trimmed
        searchResults.removeAll()
        searchIndex = 0
        
        guard !trimmed.isEmpty else { return }
        
        isSearching = true
        defer { isSearching = false }
        
        let results = doc.findString(trimmed, withOptions: [.caseInsensitive])
        // Style highlights in a readable, non-intrusive color.
        results.forEach { $0.color = NSColor.systemOrange.withAlphaComponent(0.5) }
        searchResults = results
        
        // Auto-jump to first match.
        if !results.isEmpty { focusCurrentSearchSelection() }
    }
    
    func clearSearch() {
        searchQuery = ""
        searchResults.removeAll()
        searchIndex = 0
    }
    
    func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        searchIndex = (searchIndex + 1) % searchResults.count
        focusCurrentSearchSelection()
    }
    
    func previousSearchResult() {
        guard !searchResults.isEmpty else { return }
        searchIndex = (searchIndex - 1 + searchResults.count) % searchResults.count
        focusCurrentSearchSelection()
    }
    
    /// Helper used by UI: the selections array for PDFViewRepresentable.
    var highlightedSelections: [PDFSelection] { searchResults }
    
    // MARK: - Bookmarks
    
    func toggleBookmark(for pageIndex: Int? = nil) {
        let page = pageIndex ?? currentPageIndex
        if bookmarks.contains(page) {
            bookmarks.remove(page)
        } else {
            bookmarks.insert(page)
        }
        persistBookmarksIfNeeded()
    }
    
    func isBookmarked(_ pageIndex: Int) -> Bool { bookmarks.contains(pageIndex) }
    
    // MARK: - Private helpers
    
    private func focusCurrentSearchSelection() {
        guard
            !searchResults.isEmpty,
            let doc = document
        else { return }
        
        let sel = searchResults[searchIndex]
        if let page = sel.pages.first {
            let idx = doc.index(for: page)
            if idx >= 0 && idx < doc.pageCount {
                currentPageIndex = idx
            }
        }
        // PDFViewRepresentable will receive these highlights via binding.
        // Programmatic “go(to:)” will be performed in the representable.
    }
    
    private func updateReadingProgress() {
        guard let doc = document, doc.pageCount > 0 else {
            readingProgress = 0
            return
        }
        readingProgress = Double(currentPageIndex + 1) / Double(doc.pageCount)
    }
    
    // MARK: - Persistence (per-URL page + bookmarks)
    
    private func persistLastPageIfNeeded() {
        guard let url = currentURL else { return }
        let key = pagePersistKey(for: url)
        UserDefaults.standard.set(currentPageIndex, forKey: key)
    }
    
    private func loadLastPage(for url: URL) -> Int? {
        let key = pagePersistKey(for: url)
        let value = UserDefaults.standard.integer(forKey: key)
        // integer(forKey:) returns 0 if missing; distinguish with a flag key
        let hasKey = UserDefaults.standard.object(forKey: key) != nil
        return hasKey ? value : nil
    }
    
    private func pagePersistKey(for url: URL) -> String {
        // Use standardized path to get a stable per-file key.
        (pagePersistKeyPrefix + (url.standardizedFileURL.path))
    }
    
    private func persistBookmarksIfNeeded() {
        guard let url = currentURL else { return }
        let key = bookmarksKey(for: url)
        let arr = Array(bookmarks)
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private func loadBookmarks(for url: URL) -> Set<Int> {
        let key = bookmarksKey(for: url)
        guard let data = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONDecoder().decode([Int].self, from: data) else {
            return []
        }
        return Set(arr)
    }
    
    private func bookmarksKey(for url: URL) -> String {
        (bookmarksKeyPrefix + (url.standardizedFileURL.path))
    }
}
