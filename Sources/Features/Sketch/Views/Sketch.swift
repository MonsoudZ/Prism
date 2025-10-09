//
//  Sketch.swift
//  Prism
//
//  Core sketching model (document/page/stroke/point) with schema versioning,
//  Codable persistence, and lightweight undo/redo.
//

import Foundation
import Combine

// MARK: - Top-level Document

public struct SketchDocument: Identifiable, Codable, Hashable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var schemaVersion: Int
    public var pages: [SketchPage]

    /// Optional PDF anchor
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

    public var isEmpty: Bool { pages.allSatisfy { $0.isEmpty } }
    public var pageCount: Int { pages.count }
}

// MARK: - Page

public struct SketchPage: Identifiable, Codable, Hashable {
    public enum Background: String, Codable, Hashable { case blank, ruled, grid, dots }
    public enum Size: String, Codable, Hashable { case letter, a4, custom }

    public let id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var title: String
    public var background: Background
    public var size: Size
    public var widthPoints: Double?
    public var heightPoints: Double?

    public var strokes: [SketchStroke]

    // Transient undo/redo stacks (not encoded)
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

    public mutating func beginStroke(tool: SketchTool, color: RGBAColor, width: Double, opacity: Double = 1.0) {
        captureUndoSnapshot()
        _redoStack.removeAll()
        let stroke = SketchStroke(tool: tool, color: color, width: width, opacity: opacity, points: [])
        strokes.append(stroke)
        updatedAt = Date()
    }

    public mutating func appendPoint(_ p: SketchPoint) {
        guard !strokes.isEmpty else { return }
        strokes[strokes.count - 1].points.append(p)
        updatedAt = Date()
    }

    public mutating func endStroke() {
        updatedAt = Date()
    }

    public mutating func removeLastStroke() {
        guard !strokes.isEmpty else { return }
        captureUndoSnapshot()
        _redoStack.removeAll()
        _ = strokes.popLast()
        updatedAt = Date()
    }

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
        if _undoStack.count > 50 { _undoStack.removeFirst() }
    }

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
    public var pressure: Double?
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
        self.x = x; self.y = y
        self.pressure = pressure
        self.azimuth = azimuth
        self.altitude = altitude
        self.timestamp = timestamp
    }
}

// MARK: - Tool & Color

public enum SketchTool: String, Codable, Hashable {
    case pen, highlighter, eraser, shape, text
}

public struct RGBAColor: Codable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let black = RGBAColor(r: 0, g: 0, b: 0)
    public static let yellowHighlighter = RGBAColor(r: 1.0, g: 0.95, b: 0.3, a: 0.35)
    public static let red = RGBAColor(r: 1, g: 0, b: 0)
    public static let blue = RGBAColor(r: 0.12, g: 0.44, b: 1.0)
}

// MARK: - Store

@MainActor
public final class SketchStore: ObservableObject {
    @Published public private(set) var document: SketchDocument

    public init(document: SketchDocument = .init()) {
        self.document = document
    }

    // Page management
    public func addPage(background: SketchPage.Background = .blank, size: SketchPage.Size = .letter) {
        document.pages.append(SketchPage(background: background, size: size))
        document.updatedAt = Date()
    }

    public func removePage(id: UUID) {
        if let idx = document.pages.firstIndex(where: { $0.id == id }),
           document.pages.count > 1 {
            document.pages.remove(at: idx)
            document.updatedAt = Date()
        }
    }

    public func pageIndex(for id: UUID) -> Int? {
        document.pages.firstIndex(where: { $0.id == id })
    }

    // New mutators used by ViewModel (avoid private-setter violations)
    public func setPageTitle(pageID: UUID, title: String) {
        guard let i = pageIndex(for: pageID) else { return }
        document.pages[i].title = title
        document.updatedAt = Date()
    }

    public func setDocumentAnchor(url: URL?, pageIndex: Int?) {
        document.anchoredPDFURL = url
        document.anchoredPDFPageIndex = pageIndex
        document.updatedAt = Date()
    }

    // Stroke proxies
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
    public static func encode(_ doc: SketchDocument) throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(doc)
    }

    public static func decode(_ data: Data) throws -> SketchDocument {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        var doc = try dec.decode(SketchDocument.self, from: data)
        if doc.schemaVersion != SketchDocument.currentSchemaVersion {
            doc.schemaVersion = SketchDocument.currentSchemaVersion
        }
        return doc
    }
}
