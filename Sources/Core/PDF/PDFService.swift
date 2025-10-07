import Foundation
import PDFKit
import UIKit

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
    func renderPage(_ page: PDFPage, size: CGSize) async throws -> UIImage
    func generateThumbnail(for page: PDFPage, pageNumber: Int, size: CGSize) async throws -> PDFThumbnail
    func extractText(from page: PDFPage) -> String?
    func search(in document: PDFDocument, query: String) async throws -> [PDFSearchResult]
    func export(document: PDFDocument, options: PDFExportOptions) async throws -> URL
}

// MARK: - PDF Service Implementation

final class PDFService: PDFServiceProtocol {
    private let thumbnailCache = NSCache<NSNumber, UIImage>()
    
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
    
    func renderPage(_ page: PDFPage, size: CGSize) async throws -> UIImage {
        return try await Task.detached(priority: .userInitiated) {
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { context in
                UIColor.white.set()
                context.fill(CGRect(origin: .zero, size: size))
                
                context.cgContext.saveGState()
                
                let pageBounds = page.bounds(for: .mediaBox)
                let scale = min(size.width / pageBounds.width, size.height / pageBounds.height)
                
                context.cgContext.scaleBy(x: scale, y: scale)
                context.cgContext.translateBy(x: 0, y: pageBounds.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                
                page.draw(with: .mediaBox, to: context.cgContext)
                
                context.cgContext.restoreGState()
            }
            
            return image
        }.value
    }
    
    func generateThumbnail(for page: PDFPage, pageNumber: Int, size: CGSize) async throws -> PDFThumbnail {
        // Check cache first
        if let cachedImage = thumbnailCache.object(forKey: NSNumber(value: pageNumber)) {
            return PDFThumbnail(pageNumber: pageNumber, image: cachedImage)
        }
        
        // Generate new thumbnail
        let image = try await renderPage(page, size: size)
        
        // Cache it
        thumbnailCache.setObject(image, forKey: NSNumber(value: pageNumber))
        
        return PDFThumbnail(pageNumber: pageNumber, image: image)
    }
    
    // MARK: - Text Extraction
    
    func extractText(from page: PDFPage) -> String? {
        page.string
    }
    
    // MARK: - Search
    
    func search(in document: PDFDocument, query: String) async throws -> [PDFSearchResult] {
        return try await Task.detached(priority: .userInitiated) {
            guard !query.isEmpty else { return [] }
            
            var results: [PDFSearchResult] = []
            
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                
                let selections = page.selections(for: NSRange(location: 0, length: query.count),
                                                  for: query)
                
                for selection in selections {
                    // Get context (surrounding text)
                    let pageText = page.string ?? ""
                    let range = (pageText as NSString).range(of: query, options: .caseInsensitive)
                    
                    var context = ""
                    if range.location != NSNotFound {
                        let start = max(0, range.location - 30)
                        let end = min(pageText.count, range.location + range.length + 30)
                        let contextRange = NSRange(location: start, length: end - start)
                        context = (pageText as NSString).substring(with: contextRange)
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
    
    // MARK: - Export
    
    func export(document: PDFDocument, options: PDFExportOptions) async throws -> URL {
        return try await Task.detached(priority: .userInitiated) {
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
        guard let newDocument = PDFDocument() else {
            throw PDFServiceError.exportFailed("Failed to create new PDF document")
        }
        
        let range = options.pageRange ?? (0...document.pageCount - 1)
        
        for pageIndex in range {
            guard let page = document.page(at: pageIndex) else { continue }
            newDocument.insert(page, at: newDocument.pageCount)
        }
        
        guard newDocument.write(to: url) else {
            throw PDFServiceError.exportFailed("Failed to write PDF")
        }
    }
    
    private func exportAsImages(document: PDFDocument, to directory: URL, format: PDFExportFormat.ImageFormat, quality: CGFloat, options: PDFExportOptions) async throws {
        let range = options.pageRange ?? (0...document.pageCount - 1)
        
        for pageIndex in range {
            guard let page = document.page(at: pageIndex) else { continue }
            
            let size = page.bounds(for: .mediaBox).size
            let image = try await renderPage(page, size: size)
            
            let filename = String(format: "page_%03d", pageIndex + 1)
            let fileURL: URL
            
            switch format {
            case .png:
                fileURL = directory.appendingPathComponent("\(filename).png")
                guard let data = image.pngData() else {
                    throw PDFServiceError.exportFailed("Failed to create PNG data")
                }
                try data.write(to: fileURL)
                
            case .jpeg:
                fileURL = directory.appendingPathComponent("\(filename).jpg")
                guard let data = image.jpegData(compressionQuality: quality) else {
                    throw PDFServiceError.exportFailed("Failed to create JPEG data")
                }
                try data.write(to: fileURL)
            }
        }
    }
    
    private func exportAsText(document: PDFDocument, to url: URL, options: PDFExportOptions) throws {
        let range = options.pageRange ?? (0...document.pageCount - 1)
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
