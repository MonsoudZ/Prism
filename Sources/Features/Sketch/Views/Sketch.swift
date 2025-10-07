//
//  Sketch.swift
//  Prism
//
//  Core sketching model (document/page/stroke/point) with schema versioning,
//  Codable persistence, and lightweight undo/redo.
//
//  Why we need this:
//  - Keeps the drawing data separate from the UI so SwiftUI views stay simple.
//  - Single source of truth that can be saved atomically (JSON) and migrated later.
//  - Undo/redo at the model level so tools and canvases can share behavior.
//
//  Created by Monsoud Zanaty on 10/4/25.
//

import Foundation

// MARK: - Top-level Document

/// A full sketch document (may contain multiple pages).
public struct SketchDocument: Identifiable, Codable, Hashable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var schemaVersion: Int
    public var pages: [SketchPage]

    /// Optional linkage to a PDF location (so a sketch can be anchored to a PDF page).
    public var anchoredPDFURL: URL?
    public var anchoredPDFPageIndex: Int?

    public init(
        id: UUID = UUID(),
        title: String = "Untitled Sketch",
        createdAt: Date = .init(),
        updatedAt: Date = .init(),
        pages: [SketchPage] = [SketchPage()],
        anchoredPDFURL: URL? = nil,
        anchoredPDFPageIndex: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.schemaVersion = Self.currentSchemaVersion
        self.pages = pages
        self.anchoredPDFURL = anchoredPDFURL
        self.anchoredPDFPageIndex = anchoredPDFPageIndex
    }

    // Convenience
    public var isEmpty: Bool { pages.allSatisfy { $0.isEmpty } }
    public var pageCount: Int { pages.count }
}

// MARK: - Page

public struct SketchPage: Identifiable, Codable, Hashable {
    public enum Background: String, Codable, Hashable {
        case blank, ruled, grid, dots
    }

    public enum Size: String, Codable, Hashable {
        case letter   // 8.5x11
        case a4
        case custom   // Provide width/height in points if you support it elsewhere
    }

    public let id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var title: String
    public var background: Background
    public var size: Size
    /// Optional logical page size in points for custom sizing or export hints.
    public var widthPoints: Double?
    public var heightPoints: Double?

    /// The drawable content.
    public var strokes: [SketchStroke]

    /// Basic undo/redo stacks operating on strokes collections.
    /// These are not encoded (recreated at runtime) to keep the file small.
    public var _undoStack: [[SketchStroke]] = []
    public var _redoStack: [[SketchStroke]] = []

    public init(
        id: UUID = UUID(),
        createdAt: Date = .init(),
        updatedAt: Date = .init(),
        title: String = "",
        background: Background = .blank,
        size: Size = .letter,
        widthPoints: Double? = nil,
        heightPoints: Double? = nil,
        strokes: [SketchStroke] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.background = background
        self.size = size
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
        self.strokes = strokes
    }

    public var isEmpty: Bool { strokes.isEmpty }

    // MARK: Mutating API

    /// Start a new stroke and push an undo snapshot.
    public mutating func beginStroke(tool: SketchTool, color: RGBAColor, width: Double, opacity: Double = 1.0) {
        captureUndoSnapshot()
        _redoStack.removeAll()
        let stroke = SketchStroke(tool: tool, color: color, width: width, opacity: opacity, points: [])
        strokes.append(stroke)
        updatedAt = Date()
    }

    /// Append a point to the current (last) stroke.
    public mutating func appendPoint(_ p: SketchPoint) {
        guard !strokes.isEmpty else { return }
        strokes[strokes.count - 1].points.append(p)
        updatedAt = Date()
    }

    /// End stroke (no-op for now; reserved for tools that need finalize).
    public mutating func endStroke() {
        updatedAt = Date()
    }

    /// Remove the last stroke.
    public mutating func removeLastStroke() {
        guard !strokes.isEmpty else { return }
        captureUndoSnapshot()
        _redoStack.removeAll()
        _ = strokes.popLast()
        updatedAt = Date()
    }

    /// Clear the page.
    public mutating func clear() {
        guard !strokes.isEmpty else { return }
        captureUndoSnapshot()
        _redoStack.removeAll()
        strokes.removeAll()
        updatedAt = Date()
    }

    // MARK: Undo / Redo

    public mutating func undo() {
        guard let previous = _undoStack.popLast() else { return }
        _redoStack.append(strokes)
        strokes = previous
        updatedAt = Date()
    }

    public mutating func redo() {
        guard let next = _redoStack.popLast() else { return }
        _undoStack.append(strokes)
        strokes = next
        updatedAt = Date()
    }

    private mutating func captureUndoSnapshot() {
        _undoStack.append(strokes)
        if _undoStack.count > 50 { _undoStack.removeFirst() } // simple cap
    }

    // MARK: Codable
    // We don’t encode stacks (transient). Everything else is Codable by default.

    enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, title, background, size, widthPoints, heightPoints, strokes
    }
}

// MARK: - Stroke

public struct SketchStroke: Identifiable, Codable, Hashable {
    public let id: UUID
    public var tool: SketchTool
    public var color: RGBAColor
    public var width: Double
    public var opacity: Double
    public var points: [SketchPoint]

    public init(
        id: UUID = UUID(),
        tool: SketchTool,
        color: RGBAColor,
        width: Double,
        opacity: Double = 1.0,
        points: [SketchPoint]
    ) {
        self.id = id
        self.tool = tool
        self.color = color
        self.width = width
        self.opacity = opacity
        self.points = points
    }

    /// Quick estimate of ink path length (sum of segment lengths).
    public var estimatedLength: Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            total += (dx * dx + dy * dy).squareRoot()
        }
        return total
    }
}

// MARK: - Point

public struct SketchPoint: Codable, Hashable {
    public var x: Double
    public var y: Double
    /// Optional pressure (0…1) if provided by input device.
    public var pressure: Double?
    /// Optional azimuth/tilt info for pens; reserved for future smoothing.
    public var azimuth: Double?
    public var altitude: Double?
    public var timestamp: TimeInterval

    public init(
        x: Double,
        y: Double,
        pressure: Double? = nil,
        azimuth: Double? = nil,
        altitude: Double? = nil,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.x = x
        self.y = y
        self.pressure = pressure
        self.azimuth = azimuth
        self.altitude = altitude
        self.timestamp = timestamp
    }
}

// MARK: - Tool & Color

/// High-level tools (renderer decides how to interpret).
public enum SketchTool: String, Codable, Hashable {
    case pen
    case highlighter   // typically multiply/overlay with lower opacity
    case eraser        // view can treat this as blend-mode destinationOut
    case shape         // placeholder for rectangles/ellipses (points define path)
    case text          // reserved; text stored as stroke metadata in future
}

/// Platform-independent RGBA color.
public struct RGBAColor: Codable, Hashable {
    public var r: Double // 0…1
    public var g: Double
    public var b: Double
    public var a: Double // 0…1

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let black = RGBAColor(r: 0, g: 0, b: 0, a: 1)
    public static let yellowHighlighter = RGBAColor(r: 1.0, g: 0.95, b: 0.3, a: 0.35)
    public static let red = RGBAColor(r: 1, g: 0, b: 0, a: 1)
    public static let blue = RGBAColor(r: 0.12, g: 0.44, b: 1.0, a: 1.0)
}

// MARK: - Light-weight Store (Optional but handy)

/// Minimal in-memory store you can use with SwiftUI canvases.
/// You can replace with a fancier service later; this keeps the Views simple.
@MainActor
public final class SketchStore: ObservableObject {
    @Published public private(set) var document: SketchDocument

    public init(document: SketchDocument = .init()) {
        self.document = document
    }

    // MARK: Page management

    public func addPage(background: SketchPage.Background = .blank, size: SketchPage.Size = .letter) {
        document.pages.append(SketchPage(background: background, size: size))
        document.updatedAt = Date()
    }

    public func removePage(id: UUID) {
        if let idx = document.pages.firstIndex(where: { $0.id == id }) {
            document.pages.remove(at: idx)
            document.updatedAt = Date()
        }
    }

    public func pageIndex(for id: UUID) -> Int? {
        document.pages.firstIndex(where: { $0.id == id })
    }

    // MARK: Stroke proxy helpers (mutate a single page)

    public func beginStroke(on pageID: UUID, tool: SketchTool, color: RGBAColor, width: Double, opacity: Double = 1.0) {
        guard let i = pageIndex(for: pageID) else { return }
        document.pages[i].beginStroke(tool: tool, color: color, width: width, opacity: opacity)
        document.updatedAt = Date()
    }

    public func appendPoint(on pageID: UUID, _ p: SketchPoint) {
        guard let i = pageIndex(for: pageID) else { return }
        document.pages[i].appendPoint(p)
        document.updatedAt = Date()
    }

    public func endStroke(on pageID: UUID) {
        guard let i = pageIndex(for: pageID) else { return }
        document.pages[i].endStroke()
        document.updatedAt = Date()
    }

    public func undo(on pageID: UUID) {
        guard let i = pageIndex(for: pageID) else { return }
        document.pages[i].undo()
        document.updatedAt = Date()
    }

    public func redo(on pageID: UUID) {
        guard let i = pageIndex(for: pageID) else { return }
        document.pages[i].redo()
        document.updatedAt = Date()
    }

    public func clearPage(_ pageID: UUID) {
        guard let i = pageIndex(for: pageID) else { return }
        document.pages[i].clear()
        document.updatedAt = Date()
    }
}

// MARK: - Persistence helpers

public enum SketchCodec {
    /// Encode a document to Data (atomic write recommended by caller).
    public static func encode(_ doc: SketchDocument) throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(doc)
    }

    /// Decode a document from Data (with migration hook if needed later).
    public static func decode(_ data: Data) throws -> SketchDocument {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        var doc = try dec.decode(SketchDocument.self, from: data)
        // Simple forward path: if schema changes later, migrate here.
        if doc.schemaVersion != SketchDocument.currentSchemaVersion {
            // Add migrations as needed.
            doc.schemaVersion = SketchDocument.currentSchemaVersion
        }
        return doc
    }
}
