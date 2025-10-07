//
//  SessionData.swift
//  Prism (migrated from DevReader)
//  Created 2024 → Updated 2025
//
//  What this file does
//  -------------------
//  `SessionData` captures the minimal UI/document state needed to
//  restore a user's reading session quickly and predictably.
//  It’s intentionally lightweight and Codable so it can be saved
//  alongside a document (e.g., via EnhancedPersistenceService).
//
//  Why we need it
//  --------------
//  - Fast resume: open the PDF and land on the exact page/zoom.
//  - UX continuity: remember which panels were visible and what the user
//    was doing (notes/code/web).
//  - Future-proofing: a small schemaVersion + migration lets us evolve
//    without breaking existing users.
//

import Foundation

/// Restorable reading/session state for a single document.
struct SessionData: Codable, Equatable {

    // MARK: - Schema / Migration

    /// Bump this when you add/remove/change fields in breaking ways.
    /// Keep migrations small and local here.
    var schemaVersion: Int = 2

    // MARK: - Core document state

    /// The URL of the document this session is for.
    /// Optional to keep the type reusable for "empty" session placeholders.
    var documentURL: URL?

    /// Zero-based page index the user was last viewing.
    var currentPageIndex: Int

    /// Optional zoom factor to restore (nil = use app default).
    var zoomFactor: Double?

    // MARK: - UI state (optional, keeps resume snappy but not brittle)

    /// Which right-side tab was active ("notes", "code", "web").
    /// We keep it a string to avoid cross-module enum coupling in the model.
    var activeRightTab: String?

    /// Panel visibility flags (nil → use app defaults).
    var isLibraryVisible: Bool?
    var isRightPanelVisible: Bool?

    /// When this session was last touched; useful for MRU and cleanup.
    var lastOpened: Date

    // MARK: - Init

    init(
        schemaVersion: Int = 2,
        documentURL: URL? = nil,
        currentPageIndex: Int = 0,
        zoomFactor: Double? = nil,
        activeRightTab: String? = nil,
        isLibraryVisible: Bool? = nil,
        isRightPanelVisible: Bool? = nil,
        lastOpened: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.documentURL = documentURL
        self.currentPageIndex = max(0, currentPageIndex)
        self.zoomFactor = zoomFactor
        self.activeRightTab = activeRightTab
        self.isLibraryVisible = isLibraryVisible
        self.isRightPanelVisible = isRightPanelVisible
        self.lastOpened = lastOpened
    }

    // MARK: - Backward compatibility (DevReader v1)

    /// Minimal v1 shape so we can migrate old saves seamlessly.
    private struct V1: Codable {
        let currentPageIndex: Int
        let documentURL: URL?
    }

    /// Attempt to migrate unknown/older payloads into the current schema.
    /// Usage:
    ///   let migrated = SessionData.migrate(from: data) ?? SessionData()
    static func migrate(from data: Data) -> SessionData? {
        // Try decoding current schema first.
        if let v2 = try? JSONDecoder().decode(SessionData.self, from: data) {
            return v2
        }
        // Fallback to v1 and lift into v2 with safe defaults.
        if let v1 = try? JSONDecoder().decode(V1.self, from: data) {
            return SessionData(
                schemaVersion: 2,
                documentURL: v1.documentURL,
                currentPageIndex: v1.currentPageIndex,
                zoomFactor: nil,
                activeRightTab: "notes",
                isLibraryVisible: nil,
                isRightPanelVisible: nil,
                lastOpened: Date()
            )
        }
        return nil
    }

    // MARK: - Convenience

    /// A reasonable default session for a given URL.
    static func `default`(for url: URL?) -> SessionData {
        SessionData(
            documentURL: url,
            currentPageIndex: 0,
            zoomFactor: nil,
            activeRightTab: "notes",
            isLibraryVisible: true,
            isRightPanelVisible: true,
            lastOpened: Date()
        )
    }

    /// Returns a copy with the page updated (useful for reducer-style updates).
    func with(page index: Int) -> SessionData {
        var copy = self
        copy.currentPageIndex = max(0, index)
        copy.lastOpened = Date()
        return copy
    }

    /// Returns a copy with zoom updated.
    func with(zoom factor: Double?) -> SessionData {
        var copy = self
        copy.zoomFactor = factor
        copy.lastOpened = Date()
        return copy
    }
}
