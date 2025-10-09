//
//  ImageProcessingManager.swift
//  Prism
//
//  Purpose
//  -------
//  Small, macOS-only image/thumbnail utilities around PDFKit.
//  - Produces crisp page thumbnails at a requested size
//  - Caches results in-memory (NSCache) to avoid re-rendering
//  - Provides helpers to preheat/clear thumbnails
//
//  Why we need it
//  --------------
//  Library lists, outlines, and “recent docs” all want fast previews.
//  Rendering PDF pages repeatedly is expensive; a tiny cache keeps the UI snappy.
//

import Foundation
import AppKit
import PDFKit

enum ImageProcessingManager {
    // MARK: - Cache
    // NSCache auto-evicts under memory pressure.
    private static let cache = NSCache<NSString, NSImage>()

    /// A stable cache key that incorporates document identity (URL if available),
    /// page index, and the requested pixel size to avoid mixing sizes.
    private static func key(for page: PDFPage, size: CGSize) -> NSString {
        let idx = page.document?.index(for: page) ?? -1
        let docHint = page.document?.documentURL?.absoluteString ?? "no-url"
        let pxW = Int(size.width.rounded(.toNearestOrAwayFromZero))
        let pxH = Int(size.height.rounded(.toNearestOrAwayFromZero))
        return NSString(string: "\(docHint)#\(idx)@\(pxW)x\(pxH)")
    }

    // MARK: - Public API

    /// Returns a crisp thumbnail for a PDF page at the given **pixel** size.
    /// Uses an in-memory cache and falls back to PDFKit's thumbnail renderer.
    static func pageThumbnail(from page: PDFPage, size: CGSize) -> NSImage {
        // Guard against zero/negative sizes
        guard size.width > 0, size.height > 0 else {
            return NSImage(size: .zero)
        }

        let k = key(for: page, size: size)
        if let cached = cache.object(forKey: k) {
            return cached
        }

        // PDFKit does the right scaling when asked for a "thumbnail(of:for:)".
        // Use .mediaBox to include full page content (common for PDFs).
        let image = page.thumbnail(of: size, for: .mediaBox)

        cache.setObject(image, forKey: k)
        return image
    }

    /// Pre-renders and stores a batch of thumbnails. Useful for list preheating.
    static func preheatThumbnails(pages: [PDFPage], size: CGSize) {
        for page in pages {
            _ = pageThumbnail(from: page, size: size)
        }
    }

    /// Clears all cached images. Call when memory pressure occurs or
    /// when you know sizes/needs changed drastically.
    static func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Utilities

    /// Convenience to export a thumbnail as PNG data (for disk snapshotting if needed).
    static func pngData(from image: NSImage) -> Data? {
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let data = rep.representation(using: .png, properties: [:])
        else { return nil }
        return data
    }

    /// Derives a thumbnail size that preserves aspect ratio within a bounding box.
    /// Handy for list cells where you only know the max slot size.
    static func fittedSize(for page: PDFPage, in bounding: CGSize) -> CGSize {
        let rect = page.bounds(for: .mediaBox)
        guard rect.width > 0, rect.height > 0, bounding.width > 0, bounding.height > 0 else { return .zero }
        let scale = min(bounding.width / rect.width, bounding.height / rect.height)
        return CGSize(width: rect.width * scale, height: rect.height * scale)
    }
}
