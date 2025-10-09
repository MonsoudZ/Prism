//
//  FileService.swift
//  Prism
//
//  Cross-platform-ish (macOS-focused) file utilities used across the app.
//  - App Support / Caches / Temp path helpers
//  - Safe atomic reads/writes (with backup+replace pattern)
//  - JSON Codable save/load
//  - Security-scoped bookmark create/resolve (for user-selected files/folders)
//  - NSOpenPanel / NSSavePanel helpers (macOS)
//  - File operations: copy/move/trash, attributes, sizes
//
//  Keep this type small and static so you can call FileService.* from anywhere.
//

import Foundation
import UniformTypeIdentifiers
import AppKit

enum FileService {

    // MARK: - App directories (sandbox friendly)

    /// ~/Library/Application Support/Prism
    static func appSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        let prism = base.appendingPathComponent("Prism", isDirectory: true)
        if !FileManager.default.fileExists(atPath: prism.path) {
            try FileManager.default.createDirectory(at: prism, withIntermediateDirectories: true)
        }
        return prism
    }

    /// ~/Library/Caches/com.your.bundle.id (falls back to ~/Library/Caches)
    static func cachesDirectory() throws -> URL {
        try FileManager.default.url(for: .cachesDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
    }

    /// NSTemporaryDirectory() as URL
    static func tempDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    /// ~/Documents/Prism (optional convenience)
    static func documentsWorkspace() throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let dir = docs.appendingPathComponent("Prism", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Common subfolders we use

    static func logsDirectory() throws -> URL {
        let root = try appSupportDirectory()
        let logs = root.appendingPathComponent("Logs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: logs.path) {
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        }
        return logs
    }

    static func storageDirectory() throws -> URL {
        let root = try appSupportDirectory()
        let store = root.appendingPathComponent("Storage", isDirectory: true)
        if !FileManager.default.fileExists(atPath: store.path) {
            try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        }
        return store
    }

    // MARK: - Atomic write / read

    /// Write data atomically with a backup+replace strategy for extra safety.
    /// - Parameters:
    ///   - data: bytes to write
    ///   - url: destination file
    static func writeAtomic(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Write into a temp file in the same directory.
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)

        // Swift overlay: returns the final URL (or nil if unchanged).
        let final = try fm.replaceItemAt(url,
                                         withItemAt: tmp,
                                         backupItemName: ".\(url.lastPathComponent).bak",
                                         options: [.usingNewMetadataOnly])

        _ = final // ignore or use if you care about the system-chosen path
    }
    static func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url, options: [.mappedIfSafe])
    }


    // MARK: - Codable JSON helpers

    static func saveCodable<T: Encodable>(_ value: T, to url: URL, pretty: Bool = false) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if pretty { encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes] }
        let data = try encoder.encode(value)
        try writeAtomic(data, to: url)
    }

    static func loadCodable<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try read(url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    // MARK: - File operations

    static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    static func copyItem(at: URL, to: URL, overwrite: Bool = false) throws {
        let fm = FileManager.default
        if overwrite, fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
        let dir = to.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try fm.copyItem(at: at, to: to)
    }

    static func moveItem(at: URL, to: URL, overwrite: Bool = false) throws {
        let fm = FileManager.default
        if overwrite, fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
        let dir = to.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try fm.moveItem(at: at, to: to)
    }

    /// Send to Trash (returns the new URL in Trash if available).
    @discardableResult
    static func trashItem(_ url: URL) throws -> URL? {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }

    // MARK: - Security-scoped bookmarks

    /// Create a security-scoped bookmark for a user-selected URL.
    static func createSecurityScopedBookmark(for url: URL) -> Data? {
        // Only needed for user-selected locations; start/stop access to be safe
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            return try url.bookmarkData(options: [.withSecurityScope],
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        } catch {
            Log.error("Bookmark create failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Resolve a security-scoped bookmark back to a URL.
    /// Returns (url, isStale). Callers should recreate a new bookmark when stale==true.
    static func resolveSecurityScopedURL(from bookmark: Data) -> (url: URL?, isStale: Bool) {
        do {
            var stale = false
            let resolved = try URL(resolvingBookmarkData: bookmark,
                                   options: [.withSecurityScope],
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &stale)
            return (resolved, stale)
        } catch {
            Log.error("Bookmark resolve failed: \(error.localizedDescription)")
            return (nil, false)
        }
    }

    /// Perform work while holding security access on the URL.
    static func withSecurityAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T? {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    // MARK: - Panels (macOS)

    /// Show an open panel for picking PDFs (or any UTTypes you pass).
    static func chooseOpenURLs(allowed types: [UTType] = [UTType.pdf],
                               allowsMultiple: Bool = true,
                               canChooseDirectories: Bool = false,
                               prompt: String = "Open") async -> [URL] {
        await withCheckedContinuation { cont in
            let p = NSOpenPanel()
            p.allowsMultipleSelection = allowsMultiple
            p.canChooseFiles = true
            p.canChooseDirectories = canChooseDirectories
            p.allowedContentTypes = types
            p.prompt = prompt
            p.begin { resp in
                if resp == .OK { cont.resume(returning: p.urls) }
                else { cont.resume(returning: []) }
            }
        }
    }

    /// Show a save panel with a default file name and optional type.
    static func chooseSaveURL(suggestedName: String = "untitled",
                              allowed type: UTType? = nil,
                              prompt: String = "Save") async -> URL? {
        await withCheckedContinuation { cont in
            let p = NSSavePanel()
            p.canCreateDirectories = true
            p.nameFieldStringValue = suggestedName
            if let type { p.allowedContentTypes = [type] }
            p.prompt = prompt
            p.begin { resp in
                cont.resume(returning: resp == .OK ? p.url : nil)
            }
        }
    }

    // MARK: - Small helpers

    /// Builds a safe file URL under Storage with a subpath, creating directories as needed.
    /// Example: FileService.storageFile("notes/library.json")
    static func storageFile(_ relativePath: String) throws -> URL {
        let base = try storageDirectory()
        let url = base.appendingPathComponent(relativePath)
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return url
    }

    /// Replace a file’s extension.
    static func replacingExtension(of url: URL, with newExt: String) -> URL {
        url.deletingPathExtension().appendingPathExtension(newExt)
    }

    /// Append a suffix before the extension (foo.pdf -> foo-suffix.pdf).
    static func appendingSuffix(_ url: URL, suffix: String) -> URL {
        let base = url.deletingPathExtension().lastPathComponent + suffix
        return url.deletingLastPathComponent().appendingPathComponent(base).appendingPathExtension(url.pathExtension)
    }
}
