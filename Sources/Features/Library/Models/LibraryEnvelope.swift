//
//  LibraryEnvelope.swift
//  Prism (migrated from DevReader)
//
//  What this file is
//  ------------------
//  A small, versioned “envelope” that wraps your library items together with
//  metadata (schema version + timestamps). It lets you save/load the entire
//  library atomically and migrate older formats safely.
//
//  Why you want it
//  ---------------
//  - One file, one truth: avoids partial writes/desync.
//  - Easy migration: schemaVersion + migration helper keep you forward-compatible.
//  - Auditable: created/lastModified timestamps are handy for debugging and sync.
//

import Foundation

// MARK: - Envelope

/// Versioned container for the entire Library.
/// Keep this model tiny and stable; evolve by bumping `currentSchema`.
struct LibraryEnvelope: Codable, Equatable {
    // Bump this when you make a breaking change to the payload.
    // Use a string if you prefer semantic versions; int works too.
    static let currentSchema = "2.0"

    /// Schema this payload conforms to (stored in file).
    let schemaVersion: String

    /// Creation timestamp of this file (first time persisted).
    let createdDate: Date

    /// Last modification timestamp (updates whenever you write).
    let lastModified: Date

    /// The actual payload: your library’s items.
    let items: [LibraryItem]

    // MARK: - Designated inits

    /// Create a fresh envelope for the current schema.
    init(items: [LibraryItem]) {
        let now = Date()
        self.schemaVersion = Self.currentSchema
        self.createdDate = now
        self.lastModified = now
        self.items = items
    }

    /// Create an envelope with explicit metadata (used by migrations).
    init(schemaVersion: String, createdDate: Date, lastModified: Date, items: [LibraryItem]) {
        self.schemaVersion = schemaVersion
        self.createdDate = createdDate
        self.lastModified = lastModified
        self.items = items
    }

    // MARK: - Mutating helpers (immutable style)

    /// Return a copy with updated `lastModified` (use after editing items).
    func touched() -> LibraryEnvelope {
        LibraryEnvelope(
            schemaVersion: schemaVersion,
            createdDate: createdDate,
            lastModified: Date(),
            items: items
        )
    }

    /// Return a copy with new items and a refreshed `lastModified`.
    func replacingItems(_ newItems: [LibraryItem]) -> LibraryEnvelope {
        LibraryEnvelope(
            schemaVersion: schemaVersion,
            createdDate: createdDate,
            lastModified: Date(),
            items: newItems
        )
    }
}

// MARK: - Migration

/// Migration entry-points for decoding unknown/older payloads into a `LibraryEnvelope`.
enum LibraryMigration {
    /// Attempt to decode any supported historical format into the current envelope.
    /// Supported inputs (in order):
    /// 1) `LibraryEnvelope` (new format)
    /// 2) `[OldLibraryItem]` (legacy)
    /// 3) `[LibraryItem]` (raw array of new items without envelope)
    static func migrateLibraryData(_ data: Data) throws -> LibraryEnvelope {
        let decoder = JSONDecoder()

        // 1) Already in the new envelope format.
        if let envelope = try? decoder.decode(LibraryEnvelope.self, from: data) {
            return envelope
        }

        // 2) Legacy array of OldLibraryItem -> map to new LibraryItem -> wrap.
        if let oldItems = try? decoder.decode([OldLibraryItem].self, from: data) {
            let migrated = oldItems.map { LibraryItem.migrateFromOldFormat(oldItem: $0) }
            return LibraryEnvelope(items: migrated)
        }

        // 3) Raw array of new LibraryItem -> wrap.
        if let items = try? decoder.decode([LibraryItem].self, from: data) {
            return LibraryEnvelope(items: items)
        }

        // If we make it here, the payload is neither new nor any supported legacy form.
        throw MigrationError.unsupportedFormat
    }
}

// MARK: - Migration errors

enum MigrationError: LocalizedError {
    case unsupportedFormat
    case corruptedData

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported library data format."
        case .corruptedData:
            return "Library data is corrupted and cannot be migrated."
        }
    }
}
