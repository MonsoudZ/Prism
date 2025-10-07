//
//  NoteItem.swift
//  Prism (migrated from DevReader)
//  Created 2024 → Updated 2025
//

import Foundation

/// Atomic user annotation bound to a PDF page.
/// - Persists inside `NotesEnvelope` (single-file, atomic).
/// - `Identifiable` for SwiftUI lists, `Codable` for storage.
/// - Kept intentionally small (no heavy blobs) for fast saves.
struct NoteItem: Identifiable, Hashable, Codable {

    // MARK: - Identity

    /// Stable UUID for list diffing and cross-session identity.
    let id: UUID

    // MARK: - Content

    /// Optional display title (fallback is computed below).
    var title: String

    /// The body of the note (supports Markdown in UI; stored as plain text).
    var text: String

    /// Zero-based page index in the current PDF document.
    var pageIndex: Int

    /// Optional structural label (e.g., chapter/section heading).
    var chapter: String

    /// Creation timestamp (you may add `updatedAt` later if you need edit history).
    var date: Date

    /// Free-form tags for filtering/search.
    var tags: [String]

    // MARK: - Init

    /// Designated initializer with sensible defaults.
    init(
        id: UUID = UUID(),
        title: String = "",
        text: String,
        pageIndex: Int,
        chapter: String,
        date: Date = Date(),
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.pageIndex = pageIndex
        self.chapter = chapter
        self.date = date
        self.tags = NoteItem.normalizeTags(tags)
    }

    // MARK: - Display helpers

    /// Fallback title shown in lists when `title` is empty.
    var displayTitle: String {
        title.isEmpty ? "Note on page \(max(pageIndex, 0) + 1)" : title
    }

    /// A short snippet useful for list subtitles / quick search results.
    var snippet: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(140))
    }

    // MARK: - Tag utilities

    /// Normalizes tags to lowercased, trimmed, unique order.
    static func normalizeTags(_ tags: [String]) -> [String] {
        Array(
            Set(
                tags
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .map { $0.lowercased() }
            )
        ).sorted()
    }

    mutating func addTag(_ tag: String) {
        tags = Self.normalizeTags(tags + [tag])
    }

    mutating func removeTag(_ tag: String) {
        tags = tags.filter { $0.lowercased() != tag.lowercased() }
    }

    // MARK: - Convenience transforms

    /// Returns a copy with updated text (useful for reducer-style updates).
    func with(text newText: String) -> NoteItem {
        var copy = self
        copy.text = newText
        return copy
    }

    /// Returns a copy moved to a different page.
    func moved(toPage newIndex: Int) -> NoteItem {
        var copy = self
        copy.pageIndex = newIndex
        return copy
    }
}
