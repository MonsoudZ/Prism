import Foundation
import PDFKit
import AppKit

// MARK: - PDF Document Info

struct PDFDocumentInfo {
    let pageCount: Int
    let title: String?
    let author: String?
    let subject: String?
    let creator: String?
    let creationDate: Date?
    let modificationDate: Date?
    let fileSize: Int64
    
    init(from pdfDocument: PDFDocument, fileSize: Int64) {
        self.pageCount = pdfDocument.pageCount
        self.title = pdfDocument.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        self.author = pdfDocument.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
        self.subject = pdfDocument.documentAttributes?[PDFDocumentAttribute.subjectAttribute] as? String
        self.creator = pdfDocument.documentAttributes?[PDFDocumentAttribute.creatorAttribute] as? String
        self.creationDate = pdfDocument.documentAttributes?[PDFDocumentAttribute.creationDateAttribute] as? Date
        self.modificationDate = pdfDocument.documentAttributes?[PDFDocumentAttribute.modificationDateAttribute] as? Date
        self.fileSize = fileSize
    }
}

// MARK: - PDF Page Info

struct PDFPageInfo: Equatable {
    let pageNumber: Int
    let bounds: CGRect
    let rotation: Int
    let label: String?
    
    init(page: PDFPage, pageNumber: Int) {
        self.pageNumber = pageNumber
        self.bounds = page.bounds(for: .mediaBox)
        self.rotation = page.rotation
        self.label = page.label
    }
}

// MARK: - Text Selection

struct PDFTextSelection: Equatable {
    let text: String
    let pageNumber: Int
    let bounds: [CGRect]
    
    init(selection: PDFSelection, pageNumber: Int) {
        self.text = selection.string ?? ""
        self.pageNumber = pageNumber
        self.bounds = selection.selectionsByLine().compactMap { lineSelection in
            lineSelection.bounds(for: lineSelection.pages.first ?? PDFPage())
        }
    }
}

// MARK: - Text Search Result

struct PDFSearchResult: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let pageNumber: Int
    let bounds: CGRect
    let context: String // Surrounding text for preview
    
    init(selection: PDFSelection, pageNumber: Int, context: String = "") {
        self.text = selection.string ?? ""
        self.pageNumber = pageNumber
        if let page = selection.pages.first {
            self.bounds = selection.bounds(for: page)
        } else {
            self.bounds = .zero
        }
        self.context = context
    }
}

// MARK: - PDF Rendering Options

struct PDFRenderOptions {
    var displayMode: PDFDisplayMode
    var displayDirection: PDFDisplayDirection
    var displaysPageBreaks: Bool
    var pageBreakMargins: NSEdgeInsets
    var backgroundColor: NSColor
    var interpolationQuality: CGInterpolationQuality
    
    static let `default` = PDFRenderOptions(
        displayMode: .singlePageContinuous,
        displayDirection: .vertical,
        displaysPageBreaks: true,
        pageBreakMargins: NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10),
        backgroundColor: .textBackgroundColor,
        interpolationQuality: .high
    )
}

// MARK: - PDF View State

struct PDFViewState: Equatable {
    var currentPage: Int
    var zoomScale: CGFloat
    var scrollOffset: CGPoint
    var isSearching: Bool
    var searchQuery: String
    var searchResults: [PDFSearchResult]
    var selectedSearchResultIndex: Int?
    
    static let initial = PDFViewState(
        currentPage: 0,
        zoomScale: 1.0,
        scrollOffset: .zero,
        isSearching: false,
        searchQuery: "",
        searchResults: [],
        selectedSearchResultIndex: nil
    )
}

// MARK: - PDF Thumbnail

struct PDFThumbnail: Identifiable {
    let id: Int // Page number
    let image: NSImage
    let pageNumber: Int
    
    init(pageNumber: Int, image: NSImage) {
        self.id = pageNumber
        self.pageNumber = pageNumber
        self.image = image
    }
}

// MARK: - Annotation Overlay Data

struct AnnotationOverlay: Identifiable, Equatable {
    let id: UUID
    let type: AnnotationType
    let rect: CGRect
    let color: NSColor
    let path: NSBezierPath?
    let alpha: CGFloat
    
    init(from annotation: Annotation) {
        self.id = annotation.id
        self.type = annotation.type
        self.rect = annotation.rect
        
        // Convert AnnotationColor to NSColor
        self.color = NSColor(
            red: annotation.color.red,
            green: annotation.color.green,
            blue: annotation.color.blue,
            alpha: annotation.color.alpha
        )
        
        self.alpha = annotation.color.alpha
        
        // Deserialize bezier path if present
        if let pathString = annotation.bezierPath,
           let data = pathString.data(using: .utf8),
           let path = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSBezierPath.self, from: data) {
            self.path = path
        } else {
            self.path = nil
        }
    }
    
    static func == (lhs: AnnotationOverlay, rhs: AnnotationOverlay) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - PDF Export Options

enum PDFExportFormat {
    case pdf
    case images(format: ImageFormat, quality: CGFloat)
    case text
    
    enum ImageFormat {
        case png
        case jpeg
    }
}

struct PDFExportOptions {
    var format: PDFExportFormat
    var pageRange: ClosedRange<Int>?
    var includeAnnotations: Bool
    
    static let `default` = PDFExportOptions(
        format: .pdf,
        pageRange: nil,
        includeAnnotations: true
    )
}

// MARK: - PDF Loading State

enum PDFLoadingState: Equatable {
    case idle
    case loading(progress: Double)
    case loaded(PDFDocument)
    case failed(String)
    
    static func == (lhs: PDFLoadingState, rhs: PDFLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.loading(let p1), .loading(let p2)):
            return p1 == p2
        case (.loaded, .loaded):
            return true
        case (.failed(let e1), .failed(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
}
