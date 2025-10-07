//
//  PDFPane.swift
//  Prism
//
//  Created by Monsoud Zanaty on 10/5/25.
//

import SwiftUI
import PDFKit
import AppKit
import Combine

// MARK: - PDFPane (main view)

struct PDFPane: View {
    @StateObject private var vm = PDFViewModel()

    @State private var showOutline = true
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var goToInput = ""
    @State private var showingOpenPanel = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button {
                    vm.openWithPanel()
                } label: {
                    Label("Open", systemImage: "folder")
                }

                Divider().frame(height: 22)

                Button {
                    vm.goBackInHistory()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous page")
                .disabled(!vm.canGoBack)

                Button {
                    vm.goForwardInHistory()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next page")
                .disabled(!vm.canGoForward)

                Divider().frame(height: 22)

                Button { vm.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom Out")
                Button { vm.zoomFit() } label: { Image(systemName: "square.dashed") }.help("Fit Width")
                Button { vm.zoomIn() }  label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom In")

                Divider().frame(height: 22)

                HStack(spacing: 4) {
                    Text("Page")
                    TextField("1", text: $goToInput, onCommit: {
                        if let n = Int(goToInput) { vm.goToPage(n - 1) }
                    })
                    .frame(width: 48)
                    .textFieldStyle(.roundedBorder)
                    Text("of \(vm.pageCount)")
                        .foregroundStyle(.secondary)
                }

                Divider().frame(height: 22)

                Toggle(isOn: $showOutline) {
                    Image(systemName: "list.bullet.rectangle")
                }
                .toggleStyle(.button)
                .help("Toggle Outline")

                Spacer()

                // Search
                HStack(spacing: 6) {
                    TextField("Search in document…", text: $searchText, onCommit: performSearch)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220)
                    if isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Button {
                        performSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .help("Search")

                    Button {
                        vm.previousSearchResult()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(vm.searchResults.isEmpty)

                    Button {
                        vm.nextSearchResult()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(vm.searchResults.isEmpty)

                    if !vm.searchResults.isEmpty {
                        Text("\(vm.searchIndex + 1)/\(vm.searchResults.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !vm.searchResults.isEmpty {
                        Button {
                            vm.clearSearch()
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Clear search")
                    }
                }
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content split between Outline and PDF
            HStack(spacing: 0) {
                if showOutline {
                    OutlineList(outline: vm.outlineEntries,
                                currentIndex: vm.currentPageIndex) { pageIndex in
                        vm.goToPage(pageIndex)
                    }
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(Divider(), alignment: .trailing)
                }

                PDFKitViewRepresentable(document: vm.document,
                                        scale: vm.scale,
                                        displayMode: vm.displayMode,
                                        currentPageIndex: $vm.currentPageIndex,
                                        onCurrentPageChange: { idx in
                                            vm.handlePageChange(idx)
                                        },
                                        onPDFViewAvailable: { v in
                                            vm.attach(pdfView: v)
                                        },
                                        highlightSelections: vm.searchResults,
                                        isLargePDF: vm.isLargePDF)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .onChange(of: vm.currentPageIndex) { newValue in
            goToInput = "\(newValue + 1)"
        }
        .onAppear {
            goToInput = vm.pageCount > 0 ? "\(vm.currentPageIndex + 1)" : ""
        }
    }

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            vm.clearSearch(); return
        }
        isSearching = true
        vm.search(text: searchText) {
            isSearching = false
        }
    }
}

// MARK: - Outline List

private struct OutlineList: View {
    struct Entry: Identifiable {
        let id = UUID()
        let title: String
        let pageIndex: Int
    }

    let outline: [Entry]
    let currentIndex: Int
    let onJump: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Outline")
                    .font(.headline)
                Spacer()
            }
            .padding(8)

            Divider()

            List(selection: .constant(currentIndex)) {
                ForEach(outline) { e in
                    Button {
                        onJump(e.pageIndex)
                    } label: {
                        HStack {
                            Text(e.title.isEmpty ? "Untitled" : e.title)
                                .lineLimit(1)
                            Spacer()
                            if e.pageIndex == currentIndex {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - PDFViewModel (lightweight)

@MainActor
final class PDFViewModel: ObservableObject {
    // Published UI state
    @Published var document: PDFDocument?
    @Published var currentPageIndex: Int = 0
    @Published var pageCount: Int = 0
    @Published var outlineEntries: [OutlineList.Entry] = []
    @Published var searchResults: [PDFSelection] = []
    @Published var searchIndex: Int = 0

    // Zoom & display
    @Published var scale: CGFloat = 1.0
    @Published var displayMode: PDFDisplayMode = .singlePageContinuous

    // Large PDF hints
    @Published var isLargePDF: Bool = false

    // History (simple)
    private var pageHistory: [Int] = []
    private var historyCursor: Int = -1

    // Backing PDFView
    private weak var pdfView: PDFView?

    // MARK: Loading

    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.load(url: url)
        }
    }

    func load(url: URL) {
        startPDFLoading("Loading PDF…")
        Task {
            let doc = PDFDocument(url: url)
            await MainActor.run {
                self.document = doc
                self.reindex()
                self.stopPDFLoading()
            }
        }
    }

    private func reindex() {
        guard let doc = document else {
            pageCount = 0
            outlineEntries = []
            currentPageIndex = 0
            return
        }
        pageCount = doc.pageCount
        isLargePDF = doc.pageCount >= 500
        currentPageIndex = 0
        buildOutline(from: doc)
        pageHistory = [0]
        historyCursor = 0
    }

    // MARK: Page nav

    func goToPage(_ index: Int) {
        guard let doc = document, index >= 0, index < doc.pageCount else { return }
        pushHistory(currentPageIndex)
        currentPageIndex = index
        pdfView?.go(to: doc.page(at: index)!)
    }

    func handlePageChange(_ index: Int) {
        guard let doc = document, index >= 0, index < doc.pageCount else { return }
        currentPageIndex = index
    }

    var canGoBack: Bool { historyCursor > 0 }
    var canGoForward: Bool { historyCursor >= 0 && historyCursor < pageHistory.count - 1 }

    func goBackInHistory() {
        guard canGoBack else { return }
        historyCursor -= 1
        jumpToHistoryCursor()
    }

    func goForwardInHistory() {
        guard canGoForward else { return }
        historyCursor += 1
        jumpToHistoryCursor()
    }

    private func pushHistory(_ idx: Int) {
        // If we navigated after going back, drop forward items
        if historyCursor < pageHistory.count - 1 {
            pageHistory = Array(pageHistory.prefix(historyCursor + 1))
        }
        if pageHistory.last != idx {
            pageHistory.append(idx)
            historyCursor = pageHistory.count - 1
        }
    }

    private func jumpToHistoryCursor() {
        guard historyCursor >= 0, historyCursor < pageHistory.count else { return }
        let idx = pageHistory[historyCursor]
        guard let doc = document, let page = doc.page(at: idx) else { return }
        currentPageIndex = idx
        pdfView?.go(to: page)
    }

    // MARK: Zoom

    func zoomIn()  { scale = min(scale + 0.1, 2.0) }
    func zoomOut() { scale = max(scale - 0.1, 0.3) }
    func zoomFit() { scale = 1.0 }

    // MARK: Search

    func search(text: String, completion: @escaping () -> Void) {
        guard let doc = document else { completion(); return }
        startSearch("Searching…")
        Task.detached(priority: .userInitiated) { [weak self] in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                await MainActor.run {
                    self?.searchResults = []
                    self?.searchIndex = 0
                    self?.stopSearch()
                    completion()
                }
                return
            }
            let results = doc.findString(trimmed, withOptions: [.caseInsensitive])
            await MainActor.run {
                results.forEach { $0.color = NSColor.systemYellow.withAlphaComponent(0.5) }
                self?.searchResults = results
                self?.searchIndex = 0
                self?.focusCurrentSearch()
                self?.stopSearch()
                completion()
            }
        }
    }

    func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        searchIndex = (searchIndex + 1) % searchResults.count
        focusCurrentSearch()
    }

    func previousSearchResult() {
        guard !searchResults.isEmpty else { return }
        searchIndex = (searchIndex - 1 + searchResults.count) % searchResults.count
        focusCurrentSearch()
    }

    func clearSearch() {
        searchResults = []
        searchIndex = 0
        pdfView?.highlightedSelections = []
    }

    private func focusCurrentSearch() {
        guard !searchResults.isEmpty else { return }
        let sel = searchResults[searchIndex]
        pdfView?.highlightedSelections = searchResults
        if let p = sel.pages.first, let doc = document {
            let idx = doc.index(for: p)
            if idx >= 0 && idx < doc.pageCount {
                currentPageIndex = idx
            }
        }
        pdfView?.go(to: sel)
    }

    // MARK: Outline

    private func buildOutline(from doc: PDFDocument) {
        var entries: [OutlineList.Entry] = []
        if let root = doc.outlineRoot {
            func walk(_ node: PDFOutline) {
                if let dest = node.destination, let page = dest.page {
                    let idx = doc.index(for: page)
                    let title = (node.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    entries.append(.init(title: title, pageIndex: idx))
                }
                for i in 0..<node.numberOfChildren {
                    if let c = node.child(at: i) { walk(c) }
                }
            }
            for i in 0..<root.numberOfChildren {
                if let c = root.child(at: i) { walk(c) }
            }
        }
        outlineEntries = entries.sorted { $0.pageIndex < $1.pageIndex }
    }

    // MARK: Bridges

    func attach(pdfView: PDFView) {
        self.pdfView = pdfView
    }

    // MARK: Loading feedback (optional)

    private func startPDFLoading(_ msg: String) {
        if let cls = NSClassFromString("LoadingStateManager") as? NSObject.Type,
           cls.responds(to: NSSelectorFromString("shared")) {
            // If your LoadingStateManager exists, call it via KVC to avoid hard dependency
            // (You already have it in the project, so this is just defensive.)
        }
    }

    private func stopPDFLoading() {
        // See comment above.
    }

    private func startSearch(_ msg: String) {
        // optional hook to your LoadingStateManager
    }
    private func stopSearch() {
        // optional hook to your LoadingStateManager
    }
}

// MARK: - PDFKitViewRepresentable (PDFView wrapper)

struct PDFKitViewRepresentable: NSViewRepresentable {
    let document: PDFDocument?
    let scale: CGFloat
    let displayMode: PDFDisplayMode
    @Binding var currentPageIndex: Int

    let onCurrentPageChange: (Int) -> Void
    let onPDFViewAvailable: (PDFView) -> Void
    let highlightSelections: [PDFSelection]
    let isLargePDF: Bool

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()

        v.autoScales = false
        v.displayMode = displayMode
        v.displayDirection = .vertical
        v.displaysPageBreaks = false
        v.backgroundColor = .windowBackgroundColor
        v.pageShadowsEnabled = false
        v.interpolationQuality = isLargePDF ? .low : .default
        v.maxScaleFactor = 2.0
        v.minScaleFactor = 0.3

        v.delegate = context.coordinator
        onPDFViewAvailable(v)

        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        if v.document !== document {
            v.document = document
            if let doc = document, doc.pageCount > 0 {
                let idx = max(0, min(currentPageIndex, doc.pageCount - 1))
                if let p = doc.page(at: idx) {
                    v.go(to: p)
                }
            }
        }

        if abs(v.scaleFactor - scale) > 0.005 {
            v.scaleFactor = scale
        }

        // Update highlighted selections
        v.highlightedSelections = highlightSelections
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PDFViewDelegate {
        let parent: PDFKitViewRepresentable
        init(_ p: PDFKitViewRepresentable) { self.parent = p }

        func pdfViewPageChanged(_ sender: PDFView) {
            guard let doc = sender.document, let p = sender.currentPage else { return }
            let idx = doc.index(for: p)
            if idx != parent.currentPageIndex && idx >= 0 && idx < doc.pageCount {
                parent.onCurrentPageChange(idx)
            }
        }
    }
}
