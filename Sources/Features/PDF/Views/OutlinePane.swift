//
//  OutlinePane.swift
//  Prism
//
//  Created by Monsoud Zanaty on 10/5/25.
//
//  A clean, modern outline sidebar for macOS that:
//   • Reads a PDFKit outline tree (PDFOutline) and renders it as a collapsible list
//   • Tracks/updates the current page
//   • Lets users filter (search) outline items
//   • Jumps to pages via a callback
//   • Highlights the currently-visible outline entry
//
//  Drop into: Prism/Features/PDF/OutlinePane.swift
//  Dependencies: PDFKit, SwiftUI
//

import SwiftUI
import PDFKit

// MARK: - OutlinePane (public entry)

/// Sidebar outline for a PDF document.
/// - Parameters:
///   - document: The current `PDFDocument` (optional; updates are handled).
///   - currentPageIndex: Binding to the current page index (used to highlight selection).
///   - onJump: Callback invoked when the user selects an outline item that has a page.
struct OutlinePane: View {
    // External inputs
    let document: PDFDocument?
    @Binding var currentPageIndex: Int
    let onJump: (Int) -> Void

    // Local state / view model
    @StateObject private var vm: OutlineViewModel

    // We need a custom initializer to seed StateObject with `document`
    init(document: PDFDocument?, currentPageIndex: Binding<Int>, onJump: @escaping (Int) -> Void) {
        self.document = document
        self._currentPageIndex = currentPageIndex
        self.onJump = onJump
        _vm = StateObject(wrappedValue: OutlineViewModel(document: document))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header / Filter
            HStack(spacing: 8) {
                Text("Outline")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField("Filter headings…", text: $vm.filter)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider()

            // Scrollable tree
            ScrollViewReader { proxy in
                List {
                    if vm.filteredRoots.isEmpty {
                        Text(vm.filter.isEmpty ? "No outline found" : "No matches")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        OutlineTree(
                            nodes: vm.filteredRoots,
                            currentPageIndex: $currentPageIndex,
                            onToggle: { node in vm.toggle(node) },
                            onJump: onJump
                        )
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: currentPageIndex) { _ in
                    // Optionally auto-reveal current item (no jump—just highlight)
                    if let id = vm.nodeIDForPage(currentPageIndex) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: document) { newDoc in
            vm.updateDocument(newDoc)
        }
        .onAppear {
            vm.updateDocument(document)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document Outline")
        .accessibilityHint("Browse headings and jump to pages")
    }
}

// MARK: - View Model

/// Flattens and manages a PDF outline tree, expansion state, and filtering.
@MainActor
final class OutlineViewModel: ObservableObject {
    // Public state for the view
    @Published var roots: [OutlineNode] = []
    @Published var filter: String = ""

    // Derived (filtered) tree
    var filteredRoots: [OutlineNode] {
        guard !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return roots
        }
        return roots.compactMap { filteredCopy(of: $0, matching: filter) }
    }

    private weak var document: PDFDocument?

    init(document: PDFDocument?) {
        updateDocument(document)
    }

    // Update the PDF and rebuild the outline
    func updateDocument(_ doc: PDFDocument?) {
        self.document = doc
        self.roots = buildTree(from: doc)
        // default expand top-level for quick scan
        for i in roots.indices {
            roots[i].isExpanded = true
        }
    }

    // Toggle expansion
    func toggle(_ node: OutlineNode) {
        guard let idx = indexPath(of: node, in: &roots) else { return }
        toggle(at: idx, in: &roots)
    }

    // Find a node id for page -> to auto-reveal in list
    func nodeIDForPage(_ pageIndex: Int) -> OutlineNode.ID? {
        func search(_ arr: [OutlineNode]) -> OutlineNode.ID? {
            for n in arr {
                if n.pageIndex == pageIndex { return n.id }
                if let id = search(n.children) { return id }
            }
            return nil
        }
        return search(filteredRoots)
    }

    // MARK: - Build tree from PDFOutline

    private func buildTree(from document: PDFDocument?) -> [OutlineNode] {
        guard let doc = document, let root = doc.outlineRoot else { return [] }
        var entries: [OutlineNode] = []
        for i in 0..<root.numberOfChildren {
            if let child = root.child(at: i) {
                if let node = makeNode(from: child, in: doc, depth: 0) {
                    entries.append(node)
                }
            }
        }
        return entries
    }

    private func makeNode(from outline: PDFOutline, in doc: PDFDocument, depth: Int) -> OutlineNode? {
        // Title
        let rawTitle = (outline.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? "Untitled" : rawTitle

        // Page index (if any)
        var idx: Int?
        if let dest = outline.destination, let page = dest.page {
            let i = doc.index(for: page)
            idx = i >= 0 ? i : nil
        }

        // Children
        var children: [OutlineNode] = []
        for i in 0..<outline.numberOfChildren {
            if let c = outline.child(at: i), let cNode = makeNode(from: c, in: doc, depth: depth + 1) {
                children.append(cNode)
            }
        }

        return OutlineNode(
            title: title,
            pageIndex: idx,
            depth: depth,
            isExpanded: false,
            children: children
        )
    }

    // MARK: - Filter support

    private func filteredCopy(of node: OutlineNode, matching query: String) -> OutlineNode? {
        let q = query.lowercased()
        let matchesSelf = node.title.lowercased().contains(q)

        let filteredChildren = node.children.compactMap { filteredCopy(of: $0, matching: q) }
        if matchesSelf || !filteredChildren.isEmpty {
            var copy = node
            copy.children = filteredChildren
            // auto-expand nodes along filtered path for visibility
            copy.isExpanded = true
            return copy
        }
        return nil
    }

    // MARK: - Tree utilities (index path lookups)

    private typealias IndexPath = [Int]

    private func indexPath(of target: OutlineNode, in array: inout [OutlineNode]) -> IndexPath? {
        for (i, node) in array.enumerated() {
            if node.id == target.id { return [i] }
            var childArray = node.children
            if let childPath = indexPath(of: target, in: &childArray) {
                return [i] + childPath
            }
        }
        return nil
    }

    private func toggle(at indexPath: IndexPath, in array: inout [OutlineNode]) {
        guard let first = indexPath.first else { return }
        if indexPath.count == 1 {
            array[first].isExpanded.toggle()
        } else {
            var node = array[first]
            toggle(at: Array(indexPath.dropFirst()), in: &node.children)
            array[first] = node
        }
    }
}

// MARK: - OutlineNode (tree model)

/// A lightweight, SwiftUI-friendly outline node.
struct OutlineNode: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var pageIndex: Int?              // Nil if this node doesn't point to a page
    var depth: Int                   // For styling/indent
    var isExpanded: Bool
    var children: [OutlineNode]

    var isLeaf: Bool { children.isEmpty }
}

// MARK: - OutlineTree (recursive renderer)

/// Renders a tree of `OutlineNode` with DisclosureGroups and proper indentation.
/// Highlights the node that matches `currentPageIndex`.
private struct OutlineTree: View {
    let nodes: [OutlineNode]
    @Binding var currentPageIndex: Int
    let onToggle: (OutlineNode) -> Void
    let onJump: (Int) -> Void

    var body: some View {
        ForEach(nodes) { node in
            OutlineRow(
                node: node,
                isActive: node.pageIndex == currentPageIndex,
                onToggle: { onToggle(node) },
                onJump: onJump
            )

            if node.isExpanded && !node.children.isEmpty {
                OutlineTree(nodes: node.children,
                            currentPageIndex: $currentPageIndex,
                            onToggle: onToggle,
                            onJump: onJump)
            }
        }
    }
}

// MARK: - OutlineRow (single item)

private struct OutlineRow: View {
    let node: OutlineNode
    let isActive: Bool
    let onToggle: () -> Void
    let onJump: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Indent based on depth
            Color.clear.frame(width: CGFloat(node.depth) * 12)

            // Disclosure chevron for non-leaf
            if !node.children.isEmpty {
                Button {
                    onToggle()
                } label: {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(node.isExpanded ? "Collapse" : "Expand")
            } else {
                // Align with disclosure button slot
                Color.clear.frame(width: 16)
            }

            // Title + page badge (if any)
            Button {
                if let p = node.pageIndex { onJump(p) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(node.title)
                        .lineLimit(1)
                        .font(isActive ? .body.weight(.semibold) : .body)

                    if let idx = node.pageIndex {
                        Text("\(idx + 1)")
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(isActive ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                            )
                            .foregroundStyle(isActive ? .accent : .secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if isActive {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.accent)
            }
        }
        .id(node.id)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .background(isActive ? Color.accentColor.opacity(0.06) : .clear)
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.title)\(node.pageIndex != nil ? ", page \(node.pageIndex! + 1)" : "")")
        .accessibilityHint(node.children.isEmpty ? "Jump to page" : (node.isExpanded ? "Collapse section" : "Expand section"))
    }
}
