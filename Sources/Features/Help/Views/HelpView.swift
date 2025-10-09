//
//  HelpView.swift
//  Prism
//
//  Searchable help panel.
//

import SwiftUI
import Combine

@MainActor
final class HelpViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [HelpTopic] = []

    private var allTopics: [HelpTopic] = [
        .init(title: "Open a PDF", text: "Use File → Open PDF… (⌘O) or drag a PDF into the window."),
        .init(title: "Import PDFs", text: "File → Import PDFs… (⌘I) to add multiple files to the Library."),
        .init(title: "Find in PDF", text: "Press ⌘F to open search, use ↑/↓ or Enter to navigate results."),
        .init(title: "Notes", text: "Create a sticky note with ⇧⌘N or capture a highlight with ⇧⌘H."),
        .init(title: "Library", text: "Toggle the Library sidebar with ⌘L to browse your documents."),
        .init(title: "Settings", text: "Prism → Settings… (⌘,) to customize preferences.")
    ]

    private var cancellables = Set<AnyCancellable>()

    init() {
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(180), scheduler: DispatchQueue.main)
            .sink { [weak self] q in
                guard let self else { return }
                let needle = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if needle.isEmpty {
                    self.results = self.allTopics
                } else {
                    self.results = self.allTopics.filter {
                        $0.title.lowercased().contains(needle) || $0.text.lowercased().contains(needle)
                    }
                }
            }
            .store(in: &cancellables)

        results = allTopics
    }
}

struct HelpTopic: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let text: String
}

struct HelpView: View {
    @StateObject private var model = HelpViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("Prism Help")
                    .font(.title2).bold()
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding(12)

            Divider()

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                TextField("Search help…", text: $model.query)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Results
            List(model.results) { topic in
                VStack(alignment: .leading, spacing: 6) {
                    Text(topic.title).font(.headline)
                    Text(topic.text).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
