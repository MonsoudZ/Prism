//
//  SketchViewModel.swift
//  Prism
//
//  A macOS-friendly ViewModel that coordinates the Sketch model with SwiftUI views.
//  - Holds the active tool, color, width, opacity, and selected page
//  - Exposes begin/move/end stroke methods for your canvas gesture handlers
//  - Provides undo/redo, clear page, page management
//  - Handles autosave with debounce and atomic writes
//  - Supports loading/saving documents, and anchoring to a PDF page
//
//  Created by Monsoud Zanaty on 10/4/25.
//

import Foundation
import Combine

@MainActor
public final class SketchViewModel: ObservableObject {

    // MARK: - Published State (bind to SwiftUI)
    @Published public private(set) var store: SketchStore
    @Published public var currentPageID: UUID
    @Published public var activeTool: SketchTool = .pen
    @Published public var strokeColor: RGBAColor = .black
    @Published public var strokeWidth: Double = 2.0
    @Published public var strokeOpacity: Double = 1.0

    // UI helpers
    @Published public var isDrawing = false
    @Published public var isDirty = false
    @Published public private(set) var fileURL: URL?  // where this doc is saved on disk

    // Autosave
    @Published public var autosaveEnabled: Bool = true
    @Published public var autosaveDebounceSeconds: TimeInterval = 1.0

    // MARK: - Private
    private var cancellables = Set<AnyCancellable>()
    private var saveDebounce: AnyCancellable?

    // MARK: - Init

    public init(document: SketchDocument = .init(), fileURL: URL? = nil) {
        let store = SketchStore(document: document)
        self.store = store
        self.fileURL = fileURL
        self.currentPageID = store.document.pages.first?.id ?? UUID() // will be fixed by ensurePage()

        ensurePage()
        wireAutosave()
    }

    // MARK: - Page Management

    /// Ensure we have at least one page and currentPageID is valid
    private func ensurePage() {
        if store.document.pages.isEmpty {
            store.addPage(background: .blank, size: .letter)
        }
        if store.document.pages.first(where: { $0.id == currentPageID }) == nil {
            currentPageID = store.document.pages.first!.id
        }
    }

    public func addPage(background: SketchPage.Background = .blank, size: SketchPage.Size = .letter) {
        store.addPage(background: background, size: size)
        currentPageID = store.document.pages.last!.id
        markDirty()
    }

    public func removeCurrentPage() {
        let id = currentPageID
        guard store.document.pages.count > 1 else { return } // keep at least one
        store.removePage(id: id)
        currentPageID = store.document.pages.first!.id
        markDirty()
    }

    public func titleForCurrentPage() -> String {
        guard let idx = store.pageIndex(for: currentPageID) else { return "" }
        return store.document.pages[idx].title
    }

    public func setTitleForCurrentPage(_ title: String) {
        guard let idx = store.pageIndex(for: currentPageID) else { return }
        store.document.pages[idx].title = title
        store.document.updatedAt = Date()
        markDirty()
    }

    // MARK: - Drawing (hook these from your canvas gestures)

    public func beginStroke(at x: Double, y: Double, pressure: Double? = nil, azimuth: Double? = nil, altitude: Double? = nil) {
        isDrawing = true
        store.beginStroke(
            on: currentPageID,
            tool: activeTool,
            color: strokeColor,
            width: strokeWidth,
            opacity: strokeOpacity
        )
        appendPoint(at: x, y: y, pressure: pressure, azimuth: azimuth, altitude: altitude)
    }

    public func appendPoint(at x: Double, y: Double, pressure: Double? = nil, azimuth: Double? = nil, altitude: Double? = nil) {
        guard isDrawing else { return }
        store.appendPoint(on: currentPageID, SketchPoint(x: x, y: y, pressure: pressure, azimuth: azimuth, altitude: altitude))
        markDirty()
    }

    public func endStroke() {
        guard isDrawing else { return }
        isDrawing = false
        store.endStroke(on: currentPageID)
        markDirty()
    }

    public func clearCurrentPage() {
        store.clearPage(currentPageID)
        markDirty()
    }

    // MARK: - Undo / Redo

    public func undo() {
        store.undo(on: currentPageID)
        markDirty()
    }

    public func redo() {
        store.redo(on: currentPageID)
        markDirty()
    }

    // MARK: - Tool Controls

    public func setTool(_ tool: SketchTool) { activeTool = tool }
    public func setColor(_ color: RGBAColor) { strokeColor = color }
    public func setWidth(_ width: Double) { strokeWidth = max(0.1, width) }
    public func setOpacity(_ value: Double) { strokeOpacity = min(max(0.0, value), 1.0) }

    // MARK: - PDF Anchoring (optional)

    public func anchorToPDF(url: URL, pageIndex: Int) {
        store.document.anchoredPDFURL = url
        store.document.anchoredPDFPageIndex = pageIndex
        markDirty()
    }

    public func clearPDFAnchor() {
        store.document.anchoredPDFURL = nil
        store.document.anchoredPDFPageIndex = nil
        markDirty()
    }

    // MARK: - Autosave Wiring

    private func wireAutosave() {
        // Any changes to the document trigger debounced autosave
        $store
            .map { _ in () }
            .merge(with:
                $currentPageID.map { _ in () },
                $activeTool.map { _ in () },
                $strokeColor.map { _ in () },
                $strokeWidth.map { _ in () },
                $strokeOpacity.map { _ in () }
            )
            .sink { [weak self] _ in
                self?.scheduleAutosave()
            }
            .store(in: &cancellables)
    }

    private func scheduleAutosave() {
        guard autosaveEnabled else { return }
        saveDebounce?.cancel()
        let delay = max(0.1, autosaveDebounceSeconds)
        saveDebounce = Just(())
            .delay(for: .seconds(delay), scheduler: RunLoop.main)
            .sink { [weak self] in
                Task { @MainActor in
                    try? await self?.autosaveIfNeeded()
                }
            }
    }

    private func markDirty() {
        isDirty = true
        scheduleAutosave()
    }

    private func clearDirty() {
        isDirty = false
    }

    // MARK: - Persistence

    public func newUntitled() {
        store = SketchStore(document: .init())
        currentPageID = store.document.pages.first!.id
        fileURL = nil
        isDirty = true
    }

    /// Load a document from disk.
    public func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let doc = try SketchCodec.decode(data)
        store = SketchStore(document: doc)
        currentPageID = store.document.pages.first?.id ?? {
            let id = UUID()
            store.addPage()
            return store.document.pages.first!.id
        }()
        fileURL = url
        clearDirty()
    }

    /// Save to the existing fileURL or throw if missing.
    @discardableResult
    public func save() throws -> URL {
        guard let url = fileURL else {
            throw NSError(domain: "SketchViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "No file URL set for save(). Use save(to:) first."])
        }
        try save(to: url)
        return url
    }

    /// Save to a specific URL and adopt it as the working file.
    public func save(to url: URL) throws {
        let data = try SketchCodec.encode(store.document)
        try writeAtomically(data: data, to: url)
        fileURL = url
        clearDirty()
    }

    /// Debounced autosave if we have a fileURL and dirty changes.
    public func autosaveIfNeeded() async throws {
        guard isDirty, let url = fileURL else { return }
        let data = try SketchCodec.encode(store.document)
        try writeAtomically(data: data, to: url)
        clearDirty()
    }

    // MARK: - Atomic Write Helper

    /// Ensures the file hits the disk atomically to reduce corruption risk.
    private func writeAtomically(data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmpURL = dir.appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: tmpURL, options: .atomic)
        // Replace item to keep inode stable where possible
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        if FileManager.default.fileExists(atPath: tmpURL.path) {
            // If replace failed (older OS), move into place
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tmpURL, to: url)
        }
    }

    // MARK: - Export Utilities (optional hooks)

    /// Hook to persist an externally rendered PNG (your canvas can render and pass data here).
    public func exportPNG(_ pngData: Data, to url: URL) throws {
        try writeAtomically(data: pngData, to: url)
    }

    /// Convenient default filename for exports.
    public func suggestedExportNamePNG(for pageIndex: Int? = nil) -> String {
        let base = store.document.title.isEmpty ? "Sketch" : store.document.title
        if let i = pageIndex { return "\(base)-page-\(i + 1).png" }
        return "\(base).png"
    }
}
