//
//  ConsoleFilter.swift
//  Prism
//
//  Lightweight, composable filtering for console/log entries.
//  Use this in a Console view or diagnostics tools to filter by level,
//  subsystem/category, free-text query, time range, and include/exclude rules.
//
//  Why we need it
//  --------------
//  • Keeps filtering logic out of views (testable & reusable).
//  • Works with any ConsoleEntry model (adapters included).
//  • Fast: precomputes lowercase needles/sets; single-pass predicate.
//
//  Usage
//  -----
//  let filter = ConsoleFilter(
//      levels: [.error, .warning],
//      categories: ["PDF", "Notes"],
//      query: "bookmark",
//      dateRange: .lastHour
//  )
//  let visible = filter.apply(to: entries)
//
//  You can also build it progressively and call `predicate(entry)`.
//

import Foundation

// MARK: - ConsoleEntry Protocol

/// Minimal shape your log items should conform to.
/// If your model already has these fields, just adopt this protocol.
/// If not, use `ConsoleEntryAdapter` below.
public protocol ConsoleEntryLike {
    var date: Date { get }
    var level: ConsoleLevel { get }
    var category: String { get }
    var message: String { get }
    var metadata: [String: String] { get }  // optional extra fields to search
}

// MARK: - Severity Level

public enum ConsoleLevel: Int, CaseIterable, Comparable, Codable {
    case debug = 0
    case info
    case notice
    case warning
    case error
    case critical

    public static func < (lhs: ConsoleLevel, rhs: ConsoleLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var shortLabel: String {
        switch self {
        case .debug:    return "DBG"
        case .info:     return "INF"
        case .notice:   return "NOT"
        case .warning:  return "WRN"
        case .error:    return "ERR"
        case .critical: return "CRT"
        }
    }
}

// MARK: - Date Range Presets

public enum ConsoleDateRange: Equatable {
    case allTime
    case lastMinutes(Int)
    case lastHours(Int)
    case lastDays(Int)
    case custom(Date, Date)

    public func contains(_ date: Date, now: Date = Date()) -> Bool {
        switch self {
        case .allTime:
            return true
        case .lastMinutes(let m):
            return date >= now.addingTimeInterval(TimeInterval(-60 * m))
        case .lastHours(let h):
            return date >= now.addingTimeInterval(TimeInterval(-3600 * h))
        case .lastDays(let d):
            return date >= now.addingTimeInterval(TimeInterval(-86400 * d))
        case .custom(let start, let end):
            return (start ... end).contains(date)
        }
    }

    public static var lastHour: ConsoleDateRange { .lastHours(1) }
    public static var last24h: ConsoleDateRange { .lastHours(24) }
}

// MARK: - Filter

public struct ConsoleFilter: Equatable {
    // Positive filters
    public var minLevel: ConsoleLevel?          // keep only entries >= min level
    public var levels: Set<ConsoleLevel>        // exact set filter if non-empty
    public var categories: Set<String>          // case-insensitive contains
    public var query: String?                   // case-insensitive text query
    public var dateRange: ConsoleDateRange      // time window

    // Negative filters (exclusions win)
    public var excludedCategories: Set<String>
    public var excludedTerms: Set<String>       // if message/metadata contains → drop

    // Search options
    public var searchInMetadata: Bool
    public var wholeWord: Bool

    // Precomputed lowercase needles for speed
    private var _queryLower: String?
    private var _categoryLower: Set<String>
    private var _excludedCatLower: Set<String>
    private var _excludedTermsLower: Set<String>

    public init(
        minLevel: ConsoleLevel? = nil,
        levels: Set<ConsoleLevel> = [],
        categories: Set<String> = [],
        query: String? = nil,
        dateRange: ConsoleDateRange = .allTime,
        excludedCategories: Set<String> = [],
        excludedTerms: Set<String> = [],
        searchInMetadata: Bool = true,
        wholeWord: Bool = false
    ) {
        self.minLevel = minLevel
        self.levels = levels
        self.categories = categories
        self.query = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dateRange = dateRange
        self.excludedCategories = excludedCategories
        self.excludedTerms = excludedTerms
        self.searchInMetadata = searchInMetadata
        self.wholeWord = wholeWord

        // Precompute lowercase caches
        self._queryLower = self.query?.lowercased().nilIfEmpty
        self._categoryLower = Set(categories.map { $0.lowercased() })
        self._excludedCatLower = Set(excludedCategories.map { $0.lowercased() })
        self._excludedTermsLower = Set(excludedTerms.map { $0.lowercased() }.compactMap { $0.nilIfEmpty })
    }

    // MARK: Apply to collections

    public func apply<T: ConsoleEntryLike>(to entries: [T], now: Date = Date()) -> [T] {
        entries.filter { predicate($0, now: now) }
    }

    // MARK: Single-entry predicate

    public func predicate<T: ConsoleEntryLike>(_ entry: T, now: Date = Date()) -> Bool {
        // 1) Time window
        guard dateRange.contains(entry.date, now: now) else { return false }

        // 2) Excluded categories (case-insensitive exact match)
        if _excludedCatLower.contains(entry.category.lowercased()) {
            return false
        }

        // 3) Excluded terms (message or metadata)
        if !_excludedTermsLower.isEmpty {
            let haystack = buildSearchBlob(entry).lowercased()
            for term in _excludedTermsLower {
                if contains(haystack, needle: term, wholeWord: wholeWord) {
                    return false
                }
            }
        }

        // 4) Levels
        if let min = minLevel, entry.level < min { return false }
        if !levels.isEmpty && !levels.contains(entry.level) { return false }

        // 5) Categories (case-insensitive). If provided, require membership.
        if !_categoryLower.isEmpty && !_categoryLower.contains(entry.category.lowercased()) {
            return false
        }

        // 6) Query (message + optional metadata)
        if let q = _queryLower {
            let haystack = buildSearchBlob(entry).lowercased()
            if !contains(haystack, needle: q, wholeWord: wholeWord) {
                return false
            }
        }

        return true
    }

    // MARK: Helpers

    private func buildSearchBlob<T: ConsoleEntryLike>(_ entry: T) -> String {
        if searchInMetadata, !entry.metadata.isEmpty {
            let meta = entry.metadata
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key):\($0.value)" }
                .joined(separator: " ")
            return entry.message + " " + meta
        } else {
            return entry.message
        }
    }

    private func contains(_ haystack: String, needle: String, wholeWord: Bool) -> Bool {
        guard wholeWord else { return haystack.contains(needle) }
        // Very small whole-word matcher (ASCII-ish). Good enough for console text.
        // Splits by common non-alphanumerics and compares tokens.
        let tokens = haystack.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
        return tokens.contains { $0 == Substring(needle) }
    }
}

// MARK: - Small conveniences

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Adapter (optional)
//
// If your existing log model doesn’t conform to ConsoleEntryLike,
// wrap it with this adapter instead of changing your model.

public struct ConsoleEntryAdapter: ConsoleEntryLike {
    public let date: Date
    public let level: ConsoleLevel
    public let category: String
    public let message: String
    public let metadata: [String : String]

    public init(
        date: Date,
        level: ConsoleLevel,
        category: String,
        message: String,
        metadata: [String : String] = [:]
    ) {
        self.date = date
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
    }
}
