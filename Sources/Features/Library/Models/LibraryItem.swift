//
//  LibraryItem.swift
//  Prism (migrated from DevReader)
//  Created 2024 → Updated 2025
//

import Foundation
import os.log

/// Canonical model for a single library document (usually a PDF).
/// - Carries security-scoped bookmark data so we can reopen files in the sandbox.
/// - Persisted inside `LibraryEnvelope`.
/// - Used by lists (`Identifiable`) and saved/restored (`Codable`).
struct LibraryItem: Identifiable, Codable, Hashable {

    // MARK: - Identity & File Location

    /// UI identity for lists. We keep it as a UUID for stable diffing.
    /// NOTE: Equality/Hashable below intentionally also considers URL for de-dup affinity.
    let id: UUID

    /// Original file URL as chosen/imported by the user.
    /// Do not assume it is always reachable (user might move/delete).
    let url: URL

    /// A security-scoped bookmark to re-gain access later inside the sandbox.
    /// May be `nil` for files imported before we started storing bookmarks.
    let securityScopedBookmark: Data?

    // MARK: - Presentation & Metadata

    /// Title shown in UI. Defaults to the filename if empty.
    let title: String
    let author: String?
    let pageCount: Int
    let fileSize: Int64

    /// Timestamps
    let addedDate: Date
    let lastOpened: Date?

    /// Simple taxonomy and pinning
    let tags: [String]
    let isPinned: Bool

    /// Optional small image cache (NSImage/CGImage encoded) for list cells
    let thumbnailData: Data?

    // MARK: - Derived convenience

    /// Fallback display name for UI.
    var displayName: String {
        title.isEmpty ? url.lastPathComponent : title
    }

    /// Lowercase file extension (e.g., "pdf").
    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    /// Handy flag for filtering.
    var isPDF: Bool { fileExtension == "pdf" }

    /// Backward compatibility shim (old property name).
    var addedAt: Date { addedDate }

    // MARK: - Initializers

    /// Designated initializer.
    init(
        id: UUID = UUID(),
        url: URL,
        securityScopedBookmark: Data? = nil,
        title: String = "",
        author: String? = nil,
        pageCount: Int = 0,
        fileSize: Int64 = 0,
        addedDate: Date = Date(),
        lastOpened: Date? = nil,
        tags: [String] = [],
        isPinned: Bool = false,
        thumbnailData: Data? = nil
    ) {
        self.id = id
        self.url = url
        self.securityScopedBookmark = securityScopedBookmark
        self.title = title.isEmpty ? url.lastPathComponent : title
        self.author = author
        self.pageCount = pageCount
        self.fileSize = fileSize
        self.addedDate = addedDate
        self.lastOpened = lastOpened
        self.tags = tags
        self.isPinned = isPinned
        self.thumbnailData = thumbnailData
    }

    // MARK: - Sandbox / Bookmark helpers

    /// Create a security-scoped bookmark for the current URL.
    /// Call this when importing or when you detect `securityScopedBookmark == nil`.
    func createSecurityScopedBookmark(readOnly: Bool = true) -> Data? {
        // Try to access the resource to be able to create a bookmark with scope.
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            // Note: `.securityScopeAllowOnlyReadKey` is a bookmark creation *key*, not an option flag.
            // The correct approach for read-only is simply `.withSecurityScope`; actual read/write
            // will be dictated by your file access APIs when you open the URL later.
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            Logger(subsystem: "com.prism.app", category: "LibraryItem")
                .error("Failed to create security-scoped bookmark: \(error.localizedDescription)")
            return nil
        }
    }

    /// Resolve the URL from the stored security-scoped bookmark (if present).
    /// Falls back to `url` on failure.
    func resolveURLFromBookmark() -> URL {
        guard let bookmarkData = securityScopedBookmark else { return url }
        do {
            var isStale = false
            let resolved = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            // If stale, the caller may choose to regenerate a new bookmark via `createSecurityScopedBookmark()`.
            return resolved
        } catch {
            return url
        }
    }

    /// Convenience scoped access wrapper. Use in short blocks to avoid leaks.
    /// ```
    /// item.withScopedAccess { fileURL in
    ///     try Data(contentsOf: fileURL)
    /// }
    /// ```
    func withScopedAccess<T>(_ body: (URL) throws -> T) rethrows -> T {
        let fileURL = resolveURLFromBookmark()
        let didStart = fileURL.startAccessingSecurityScopedResource()
        defer { if didStart { fileURL.stopAccessingSecurityScopedResource() } }
        return try body(fileURL)
    }

    // MARK: - Duplicate detection

    /// Heuristic duplicate detection used by import & cleanup flows.
    /// Strategy:
    /// 1) Exact same URL
    /// 2) Same bookmark bytes (when both exist)
    /// 3) Same file attributes (size + modification date ~1s)
    func isDuplicate(of other: LibraryItem) -> Bool {
        if url == other.url { return true }

        if let b1 = securityScopedBookmark, let b2 = other.securityScopedBookmark, b1 == b2 {
            return true
        }

        // Attribute comparison is best-effort; do not throw from here.
        let fm = FileManager.default
        let a1 = (try? fm.attributesOfItem(atPath: url.path)) ?? [:]
        let a2 = (try? fm.attributesOfItem(atPath: other.url.path)) ?? [:]

        let size1 = (a1[.size] as? NSNumber)?.int64Value ?? 0
        let size2 = (a2[.size] as? NSNumber)?.int64Value ?? 0
        let m1 = a1[.modificationDate] as? Date
        let m2 = a2[.modificationDate] as? Date

        if size1 == size2 && size1 > 0,
           let d1 = m1, let d2 = m2,
           abs(d1.timeIntervalSince(d2)) < 1.0 {
            return true
        }

        return false
    }

    // MARK: - Hashable & Equatable

    /// We keep `Identifiable` on `id`, but to avoid accidental duplicates across
    /// sessions when items are reconstructed, we fold URL into hashing as well.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(url.standardizedFileURL.path.lowercased())
    }

    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        // Keep strict identity (UI selection/diffing), but allow same-file checks elsewhere via `isDuplicate`.
        lhs.id == rhs.id
    }

    // MARK: - Migration from legacy models

    /// Build a modern `LibraryItem` from an old serialized format (no bookmark field).
    static func migrateFromOldFormat(oldItem: OldLibraryItem) -> LibraryItem {
        LibraryItem(
            // new UUID per migrated row is fine; it becomes stable after first save
            url: oldItem.url,
            title: oldItem.title,
            author: oldItem.author,
            pageCount: oldItem.pageCount,
            fileSize: oldItem.fileSize,
            addedDate: oldItem.addedDate,
            lastOpened: oldItem.lastOpened,
            tags: oldItem.tags,
            isPinned: oldItem.isPinned,
            thumbnailData: oldItem.thumbnailData
        )
    }
}

// MARK: - Legacy support types (migration-only)

/// Old `LibraryItem` format without bookmark/id. Keep only for decoding old data.
struct OldLibraryItem: Codable {
    let url: URL
    let title: String
    let author: String?
    let pageCount: Int
    let fileSize: Int64
    let addedDate: Date
    let lastOpened: Date?
    let tags: [String]
    let isPinned: Bool
    let thumbnailData: Data?
}
