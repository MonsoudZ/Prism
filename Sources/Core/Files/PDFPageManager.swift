//
//  PDFPageManager.swift
//  Prism
//
//  Purpose
//  -------
//  A small, testable service that owns *all page-level concerns* for a loaded PDF:
//   • Fast page image rendering (thumbnails and page snapshots) with NSCache
//   • Smart prefetch around the current page to keep scrolling smooth
//   • Lightweight text extraction per page (for quick search previews)
//   • Memory-pressure handling to purge caches
//
//  This keeps PDFViewModel slimmer and avoids re-implementing caching logic
//  across views.
//

import Foundation
import PDFKit
import AppKit
import Combine

// MARK: - Types

enum PDFRenderQuality {
    case thumbnail     // ~250–400 px width
    case medium        // ~800–1200 px width
    case high          // ~1600–2400 px width

    var targetScale: CGFloat {
        switch self {
        case .thumbnail: return 0.3
        case .medium:    return 1.0
        case .high:      return 2.0
        }
    }
}

struct PageSnapshot: Hashable {
    let index: Int
    let image: NSImage
    let size: CGSize
}

// MARK: - Manager

@MainActor
final class PDFPageManager: ObservableObject {
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var pageTextPreview: [Int: String] = [:]

    private var document: PDFDocument?
    private var cancellables = Set<AnyCancellable>()
    private let imageCache = NSCache<NSString, NSImage>()
    private var textCache: [Int: String] = [:]
    private let renderQueue = OperationQueue()
    private let textQueue   = OperationQueue()
    private let prefetchRadius = 3
    private var inflightRenders = Set<String>()

    init() {
        renderQueue.qualityOfService = .userInitiated
        renderQueue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount - 2)
        textQueue.qualityOfService = .utility
        textQueue.maxConcurrentOperationCount = 1

        DistributedNotificationCenter.default().publisher(
            for: Notification.Name("com.apple.system.lowmemory")
        )
        .sink { [weak self] _ in self?.handleMemoryPressure() }
        .store(in: &cancellables)
    }

    deinit {
        renderQueue.cancelAllOperations()
        textQueue.cancelAllOperations()
    }

    // MARK: - Document lifecycle

    func setDocument(_ doc: PDFDocument?) {
        renderQueue.cancelAllOperations()
        textQueue.cancelAllOperations()

        document = doc
        imageCache.removeAllObjects()
        textCache.removeAll()
        pageTextPreview.removeAll()
        currentIndex = 0

        if pageCount > 0 {
            prefetch(around: 0)
            _ = snapshot(for: 0, quality: .medium) { _ in }
            _ = text(for: 0) { _ in }
        }
    }

    var pageCount: Int {
        document?.pageCount ?? 0
    }

    // MARK: - Public API

    func setVisibleIndex(_ index: Int) {
        guard index != currentIndex else { return }
        currentIndex = clamp(index, 0, pageCount - 1)
        prefetch(around: currentIndex)
    }

    @discardableResult
    func snapshot(for index: Int,
                  quality: PDFRenderQuality,
                  completion: @escaping (PageSnapshot?) -> Void) -> UUID? {
        guard let doc = document,
              (0..<pageCount).contains(index),
              let page = doc.page(at: index) else {
            completion(nil)
            return nil
        }

        let key = cacheKey(index: index, quality: quality)
        if let cached = imageCache.object(forKey: key as NSString) {
            completion(PageSnapshot(index: index, image: cached, size: cached.size))
            return nil
        }

        if inflightRenders.contains(key) {
            completion(nil)
            return nil
        }
        inflightRenders.insert(key)

        let token = UUID()
        let docRef = doc

        renderQueue.addOperation { [weak self] in
            guard let self else { return }
            let img = self.render(page: page, in: docRef, quality: quality)
            OperationQueue.main.addOperation {
                self.inflightRenders.remove(key)
                if let img {
                    self.imageCache.setObject(img, forKey: key as NSString)
                    completion(PageSnapshot(index: index, image: img, size: img.size))
                } else {
                    completion(nil)
                }
            }
        }
        return token
    }

    @discardableResult
    func text(for index: Int, completion: @escaping (String?) -> Void) -> UUID? {
        guard let doc = document,
              (0..<pageCount).contains(index),
              let page = doc.page(at: index) else {
            completion(nil)
            return nil
        }

        if let cached = textCache[index] {
            completion(cached)
            return nil
        }

        let token = UUID()
        textQueue.addOperation { [weak self] in
            guard let self else { return }
            let raw = page.string ?? ""
            let preview = raw.replacingOccurrences(of: "\\s+", with: " ",
                                                   options: .regularExpression)
            let clipped = String(preview.prefix(300))
            OperationQueue.main.addOperation {
                self.textCache[index] = clipped
                self.pageTextPreview[index] = clipped
                completion(clipped)
            }
        }
        return token
    }

    func clearImageCache() {
        imageCache.removeAllObjects()
    }

    func clearTextCache() {
        textCache.removeAll()
        pageTextPreview.removeAll()
    }

    // MARK: - Prefetching

    private func prefetch(around index: Int) {
        guard let doc = document else { return }
        let low  = max(0, index - prefetchRadius)
        let high = min(pageCount - 1, index + prefetchRadius)
        let order = (low...high).sorted { abs($0 - index) < abs($1 - index) }
        for i in order {
            guard doc.page(at: i) != nil else { continue }
            _ = snapshot(for: i, quality: .thumbnail) { _ in }
        }
    }

    // MARK: - Rendering

    private func render(page: PDFPage, in document: PDFDocument, quality: PDFRenderQuality) -> NSImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let baseWidth: CGFloat = 1000.0
        let width = max(250.0, baseWidth * quality.targetScale)
        let scale = width / bounds.width
        let targetSize = CGSize(width: bounds.width * scale,
                                height: bounds.height * scale)

        if quality == .high {
            let img = NSImage(size: targetSize)
            img.lockFocusFlipped(false)
            NSColor.clear.set()
            NSBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            let ctx = NSGraphicsContext.current?.cgContext
            ctx?.saveGState()
            ctx?.translateBy(x: 0, y: targetSize.height)
            ctx?.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx!)
            ctx?.restoreGState()
            img.unlockFocus()
            return img
        } else {
            return page.thumbnail(of: targetSize, for: .mediaBox)
        }
    }

    // MARK: - Memory pressure

    private func handleMemoryPressure() {
        imageCache.removeAllObjects()
    }

    // MARK: - Helpers

    private func cacheKey(index: Int, quality: PDFRenderQuality) -> String {
        switch quality {
        case .thumbnail: return "\(index)-t"
        case .medium:    return "\(index)-m"
        case .high:      return "\(index)-h"
        }
    }

    private func clamp(_ value: Int, _ lo: Int, _ hi: Int) -> Int {
        min(max(value, lo), hi)
    }
}
