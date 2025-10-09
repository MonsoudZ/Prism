import Foundation
import AppKit
import PDFKit

// MARK: - PDF Service Errors

enum PDFServiceError: LocalizedError {
    case documentLoadFailed
    case invalidPage(Int)
    case renderFailed
    case searchFailed
    case exportFailed(String)
    case thumbnailGenerationFailed

    var errorDescription: String? {
        switch self {
        case .documentLoadFailed:
            return "Failed to load PDF document"
        case .invalidPage(let page):
            return "Invalid page number: \(page)"
        case .renderFailed:
            return "Failed to render PDF page"
        case .searchFailed:
            return "Search operation failed"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .thumbnailGenerationFailed:
            return "Failed to generate thumbnail"
        }
    }
}

// MARK: - PDF Service Protocol

protocol PDFServiceProtocol {
    func loadDocument(from url: URL) async throws -> PDFDocument
    func extractInfo(from document: PDFDocument, fileSize: Int64) -> PDFDocumentInfo
    func extractPageInfo(from page: PDFPage, pageNumber: Int) -> PDFPageInfo
    func renderPage(_ page: PDFPage, size: CGSize) async throws -> NSImage
    func generateThumbnail(for page: PDFPage, pageNumber: Int, size: CGSize) async throws -> PDFThumbnail
    func extractText(from page: PDFPage) -> String?
    func search(in document: PDFDocument, query: String) async throws -> [PDFSearchResult]
    func export(document: PDFDocument, options: PDFExportOptions) async throws -> URL
}

// MARK: - PDF Service Implementation

final class PDFService: PDFServiceProtocol {

    // NSCache needs class types; NSImage is fine on macOS.
    private let thumbnailCache = NSCache<NSNumber, NSImage>()

    init() {
        thumbnailCache.countLimit = 50 // Cache up to 50 thumbnails
    }

    // MARK: - Document Loading

    func loadDocument(from url: URL) async throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else {
            throw PDFServiceError.documentLoadFailed
        }
        return document
    }

    // MARK: - Info Extraction

    func extractInfo(from document: PDFDocument, fileSize: Int64) -> PDFDocumentInfo {
        PDFDocumentInfo(from: document, fileSize: fileSize)
    }

    func extractPageInfo(from page: PDFPage, pageNumber: Int) -> PDFPageInfo {
        PDFPageInfo(page: page, pageNumber: pageNumber)
    }

    // MARK: - Rendering

    func renderPage(_ page: PDFPage, size: CGSize) async throws -> NSImage {
        try await Task.detached(priority: .userInitiated) {
            let image = NSImage(size: size)
            image.lockFocus()

            // Background
            NSColor.white.set()
            NSRect(origin: .zero, size: size).fill()

            guard let ctx = NSGraphicsContext.current?.cgContext else {
                image.unlockFocus()
                throw PDFServiceError.renderFailed
            }

            let pageBounds = page.bounds(for: .mediaBox)
            let scale = min(size.width / pageBounds.width, size.height / pageBounds.height)

            ctx.saveGState()
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: 0, y: pageBounds.height)
            ctx.scaleBy(x: 1, y: -1)

            page.draw(with: .mediaBox, to: ctx)

            ctx.restoreGState()
            image.unlockFocus()

            return image
        }.value
    }

    func generateThumbnail(for page: PDFPage, pageNumber: Int, size: CGSize) async throws -> PDFThumbnail {
        // Cache hit
        if let cached = thumbnailCache.object(forKey: NSNumber(value: pageNumber)) {
            return PDFThumbnail(pageNumber: pageNumber, image: cached)
        }

        // Render and cache
        let img = try await renderPage(page, size: size)
        thumbnailCache.setObject(img, forKey: NSNumber(value: pageNumber))
        return PDFThumbnail(pageNumber: pageNumber, image: img)
    }

    // MARK: - Text Extraction

    func extractText(from page: PDFPage) -> String? {
        page.string
    }

    // MARK: - Search

    func search(in document: PDFDocument, query: String) async throws -> [PDFSearchResult] {
        try await Task.detached(priority: .userInitiated) {
            guard !query.isEmpty else { return [] }

            var results: [PDFSearchResult] = []

            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }

                // Use document-driven search; filter selections to this page.
                let selections = self.selections(on: page, in: document, matching: query, options: [.caseInsensitive])

                for selection in selections {
                    // Context (surrounding text) from the page
                    let pageText = page.string ?? ""
                    let nsPageText = pageText as NSString
                    let range = nsPageText.range(of: query, options: .caseInsensitive)

                    var context = ""
                    if range.location != NSNotFound {
                        let start = max(0, range.location - 30)
                        let end = min(nsPageText.length, range.location + range.length + 30)
                        let contextRange = NSRange(location: start, length: end - start)
                        context = nsPageText.substring(with: contextRange)
                    }

                    let result = PDFSearchResult(
                        selection: selection,
                        pageNumber: pageIndex,
                        context: context
                    )
                    results.append(result)
                }
            }

            return results
        }.value
    }

    /// Page-scoped search via the document’s find API (since PDFPage doesn’t expose `selections(...)` on macOS).
    private func selections(on page: PDFPage,
                            in document: PDFDocument,
                            matching query: String,
                            options: NSString.CompareOptions = [.caseInsensitive]) -> [PDFSelection] {
        var hits: [PDFSelection] = []
        var cursor: PDFSelection? = nil
        while let sel = document.findString(query, fromSelection: cursor, withOptions: options) {
            if sel.pages.contains(page) { hits.append(sel) }
            cursor = sel
        }
        return hits
    }

    // MARK: - Export

    func export(document: PDFDocument, options: PDFExportOptions) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let tempDir = FileManager.default.temporaryDirectory
            let exportURL: URL

            switch options.format {
            case .pdf:
                exportURL = tempDir.appendingPathComponent("export_\(UUID().uuidString).pdf")
                try self.exportAsPDF(document: document, to: exportURL, options: options)

            case .images(let format, let quality):
                let dirURL = tempDir.appendingPathComponent("export_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                try await self.exportAsImages(document: document, to: dirURL, format: format, quality: quality, options: options)
                exportURL = dirURL

            case .text:
                exportURL = tempDir.appendingPathComponent("export_\(UUID().uuidString).txt")
                try self.exportAsText(document: document, to: exportURL, options: options)
            }

            return exportURL
        }.value
    }

    private func exportAsPDF(document: PDFDocument, to url: URL, options: PDFExportOptions) throws {
        // PDFDocument() is non-failable on macOS
        let newDocument = PDFDocument()

        let range = options.pageRange ?? (0...(document.pageCount - 1))
        for pageIndex in range {
            guard let page = document.page(at: pageIndex) else { continue }
            newDocument.insert(page, at: newDocument.pageCount)
        }

        guard newDocument.write(to: url) else {
            throw PDFServiceError.exportFailed("Failed to write PDF")
        }
    }

    private func exportAsImages(document: PDFDocument,
                                to directory: URL,
                                format: PDFExportFormat.ImageFormat,
                                quality: CGFloat,
                                options: PDFExportOptions) async throws {
        let range = options.pageRange ?? (0...(document.pageCount - 1))

        for pageIndex in range {
            guard let page = document.page(at: pageIndex) else { continue }

            let size = page.bounds(for: .mediaBox).size
            let image = try await renderPage(page, size: size)

            let filename = String(format: "page_%03d", pageIndex + 1)
            let fileURL: URL

            switch format {
            case .png:
                fileURL = directory.appendingPathComponent("\(filename).png")
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let data = rep.representation(using: .png, properties: [:]) else {
                    throw PDFServiceError.exportFailed("Failed to create PNG data")
                }
                try data.write(to: fileURL)

            case .jpeg:
                fileURL = directory.appendingPathComponent("\(filename).jpg")
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
                    throw PDFServiceError.exportFailed("Failed to create JPEG data")
                }
                try data.write(to: fileURL)
            }
        }
    }

    private func exportAsText(document: PDFDocument, to url: URL, options: PDFExportOptions) throws {
        let range = options.pageRange ?? (0...(document.pageCount - 1))
        var text = ""

        for pageIndex in range {
            guard let page = document.page(at: pageIndex) else { continue }
            if let pageText = page.string {
                text += "--- Page \(pageIndex + 1) ---\n\n"
                text += pageText
                text += "\n\n"
            }
        }

        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
