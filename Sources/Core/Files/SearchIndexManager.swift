//
//  SearchIndexManager.swift
//  Prism
//
//  Created by Monsoud Zanaty on 10/4/25.
//

import Foundation
import Combine

/// Lightweight, in-memory search index for PDFs/notes.
/// - Scopes results per document ID (UUID).
/// - Publishes indexing state so UI can show progress spinners.
/// - This is intentionally simple; you can swap with a richer indexer later.
@MainActor
final class SearchIndexManager: ObservableObject {
    static let shared = SearchIndexManager()
    
    @Published private(set) var isIndexing: Bool = false
    @Published private(set) var lastIndexedAt: Date?
    
    /// The searchable text per document.
    private var corpus: [UUID: String] = [:]
    
    private init() {}
    
    // MARK: - Indexing
    
    /// Replace or create the index for a document.
    func indexDocument(id: UUID, fullText: String) {
        isIndexing = true
        defer {
            isIndexing = false
            lastIndexedAt = Date()
        }
        corpus[id] = fullText
    }
    
    /// Remove a document from the index.
    func removeDocument(id: UUID) {
        corpus[id] = nil
    }
    
    /// Clear all indexes.
    func clear() {
        corpus.removeAll()
        lastIndexedAt = nil
        isIndexing = false
    }
    
    // MARK: - Query
    
    /// Very basic substring search. Returns the matched ranges in the source String.
    /// For the UI, you’ll likely map these to page hits elsewhere.
    func search(_ query: String, in id: UUID, caseInsensitive: Bool = true, maxResults: Int = 200) -> [Range<String.Index>] {
        guard let text = corpus[id], !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let haystack = text as NSString
        let options: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []
        
        var ranges: [Range<String.Index>] = []
        var searchRange = NSRange(location: 0, length: haystack.length)
        
        while let found = haystack.range(of: query, options: options, range: searchRange).toOptional(), found.length > 0 {
            if let swiftRange = Range(found, in: text) {
                ranges.append(swiftRange)
            }
            if ranges.count >= maxResults { break }
            let nextLocation = found.location + max(1, found.length)
            if nextLocation >= haystack.length { break }
            searchRange = NSRange(location: nextLocation, length: haystack.length - nextLocation)
        }
        return ranges
    }
}

// MARK: - Small bridging helper

private extension NSRange {
    func toOptional() -> NSRange? {
        location != NSNotFound ? self : nil
    }
}

