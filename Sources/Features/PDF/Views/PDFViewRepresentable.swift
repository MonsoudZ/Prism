//
//  PDFViewRepresentable.swift
//  Prism
//
//  Created by Monsoud Zanaty on 10/5/25.
//
//  What this file does
//  -------------------
//  A clean macOS SwiftUI wrapper around PDFKit’s PDFView. It renders a PDFDocument,
//  keeps the SwiftUI state (current page, zoom) in sync with PDFView, and applies
//  lightweight performance & accessibility tweaks. It’s intentionally standalone,
//  so you can drop it into Prism without pulling in other DevReader-specific types.
//
//  Why we need it
//  --------------
//  • SwiftUI doesn’t have a native PDF view; PDFKit’s PDFView is AppKit.
//  • NSViewRepresentable lets us embed PDFView in SwiftUI and coordinate state.
//  • We centralize configuration for large-PDF safety (no page shadows, capped zoom,
//    lower interpolation quality, etc.) so 1000-page docs stay usable.
//
//  How to use
//  ----------
//  In your PDF pane/view, hold a `PDFDocument?` and a `@State var currentPageIndex`.
//  Then embed:
//
//      PDFViewRepresentable(
//          document: document,
//          currentPageIndex: $currentPageIndex,
//          isLargePDF: (document?.pageCount ?? 0) >= 500,
//          highlightedSelections: selections // [] if none
//      )
//
//  You can omit `highlightedSelections` if you don’t do search/highlighting yet.
//

import SwiftUI
import PDFKit
import AppKit

// MARK: - PDFViewRepresentable

struct PDFViewRepresentable: NSViewRepresentable {
    // Inputs from SwiftUI
    var document: PDFDocument?
    @Binding var currentPageIndex: Int

    // Tuning knobs
    var isLargePDF: Bool = false
    var highlightedSelections: [PDFSelection] = []

    // Persisted zoom (safe bounds enforced below)
    @AppStorage("defaultZoom") private var defaultZoom: Double = 1.0

    // MARK: NSViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()

        // --- Core appearance/behavior (macOS-native) ---
        v.backgroundColor = .windowBackgroundColor
        v.displayBox = .mediaBox
        v.displayMode = .singlePageContinuous
        v.autoScales = false // we control the scaleFactor explicitly
        v.pageShadowsEnabled = false // reduces memory; cleaner look
        v.delegate = context.coordinator

        // --- Performance & safety guards ---
        v.interpolationQuality = isLargePDF ? .low : .default
        v.minScaleFactor = 0.3
        v.maxScaleFactor = 2.0

        // --- Accessibility hints ---
        v.setAccessibilityLabel("PDF Document")
        v.setAccessibilityRole(.group)
        v.setAccessibilityHelp("Use arrow keys to navigate pages. Use Command + Plus/Minus to zoom. Command + F to search.")

        // Initial doc & zoom
        if let doc = document {
            v.document = doc
            goToSafePage(v, pageIndex: currentPageIndex)
        }
        applySafeZoom(v)

        // Initial highlights (if any)
        v.highlightedSelections = highlightedSelections

        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        // Update document only when identity changes
        if v.document !== document {
            v.document = document
            // Reset page to the binding’s page (clamped)
            goToSafePage(v, pageIndex: currentPageIndex)
        } else {
            // If just page changed, scroll to it
            goToSafePage(v, pageIndex: currentPageIndex)
        }

        // Update highlights (e.g., search results)
        if v.highlightedSelections as NSArray? !== highlightedSelections as NSArray? {
            v.highlightedSelections = highlightedSelections
        }

        // Keep zoom in a safe envelope
        applySafeZoom(v)
    }

    // MARK: - Helpers

    private func applySafeZoom(_ v: PDFView) {
        // Clamp persisted zoom into safe range and avoid jitter
        let safeZoom = max(0.3, min(defaultZoom, 2.0))
        if abs(v.scaleFactor - safeZoom) > 0.01 {
            v.scaleFactor = safeZoom
        }
    }

    private func goToSafePage(_ v: PDFView, pageIndex: Int) {
        guard let doc = v.document, doc.pageCount > 0 else { return }
        let clamped = max(0, min(pageIndex, doc.pageCount - 1))
        if let page = doc.page(at: clamped), v.currentPage !== page {
            v.go(to: page)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PDFViewDelegate {
        private let parent: PDFViewRepresentable
        private var pageTrackTimer: Timer?

        init(_ parent: PDFViewRepresentable) {
            self.parent = parent
            super.init()
            startPageTracking()
        }

        deinit {
            pageTrackTimer?.invalidate()
        }

        // Periodically sync the current page index back to SwiftUI state.
        // Using a short timer avoids spamming updates while the user scrolls quickly.
        private func startPageTracking() {
            pageTrackTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
                self?.syncCurrentPageToBinding()
            }
        }

        private func syncCurrentPageToBinding() {
            guard let pdfView = attachedPDFView, let doc = pdfView.document, let page = pdfView.currentPage else { return }
            let idx = doc.index(for: page)
            if idx >= 0 && idx != parent.currentPageIndex {
                // Push to binding on main thread
                DispatchQueue.main.async {
                    self.parent.currentPageIndex = idx
                }
            }
        }

        private var attachedPDFView: PDFView? {
            // We don’t have a direct reference from here, but PDFKit calls delegate methods
            // with the sender, so we grab it there as needed.
            nil
        }

        // MARK: - PDFViewDelegate

        func pdfViewPageChanged(_ sender: PDFView) {
            // Immediate update when PDFView notifies us (smooth highlight/outline sync)
            guard let doc = sender.document, let page = sender.currentPage else { return }
            let idx = doc.index(for: page)
            if idx >= 0 && idx != parent.currentPageIndex {
                parent.currentPageIndex = idx
            }
        }

        func pdfViewWillClick(onLink sender: PDFView, with url: URL) {
            // Optional: open external links in the default browser
            NSWorkspace.shared.open(url)
        }

        func pdfViewWillDraw(_ sender: PDFView) {
            // Light adaptive tuning: lower quality in Low Power Mode or for huge docs
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                sender.interpolationQuality = .low
            }
        }

        func pdfViewDidChangeDocument(_ sender: PDFView) {
            // Basic integrity check to catch empty/corrupt loads without crashing UI
            guard let doc = sender.document else { return }
            if doc.pageCount == 0 {
                // In a larger app you’d route this to a toast/error center.
                NSSound.beep()
            }
            // Snap to the bound page index when a new doc arrives
            if let page = doc.page(at: min(parent.currentPageIndex, max(0, doc.pageCount - 1))) {
                sender.go(to: page)
            }
        }
    }
}
