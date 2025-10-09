//
//  LargePDFPerformanceMonitor.swift
//  Prism
//
//  Lightweight tracker for expensive PDF operations on large documents.
//

import Foundation
import Combine
import os.log
import os.signpost

// MARK: - Public API

enum LargePDFMetric: String {
    case loadDocument
    case buildOutline
    case search
    case pageRender
}

struct LargePDFSample: Identifiable, Hashable {
    let id = UUID()
    let metric: LargePDFMetric
    let duration: TimeInterval
    let context: [String: String]
    let timestamp: Date
}

/// Singleton performance monitor (thread-safe where needed).
@MainActor
final class LargePDFPerformanceMonitor: ObservableObject {
    static let shared = LargePDFPerformanceMonitor()

    @Published private(set) var recent: [LargePDFSample] = []

    // In-flight operations keyed by token
    private var inflight: [UUID: (metric: LargePDFMetric, start: Date, context: [String: String])] = [:]

    // Keep last N samples
    private let maxSamples = 100

    // Signpost (optional)
    private let log = OSLog(subsystem: "com.yourco.prism", category: "LargePDF")

    private init() {}

    // MARK: - Timing

    /// Start timing a metric. Returns a token to be passed to `end(_:)`.
    func start(_ metric: LargePDFMetric, context: [String: String] = [:]) -> UUID {
        let token = UUID()
        let now = Date()
        inflight[token] = (metric: metric, start: now, context: context)
        if #available(iOS 12.0, macOS 10.14, *) {
            os_signpost(.begin, log: log, name: "LargePDF", "%{public}s", metric.rawValue)
        }
        return token
    }

    /// End timing and record the sample. If token not found, does nothing.
    func end(_ token: UUID) {
        guard let node = inflight.removeValue(forKey: token) else { return }
        let duration = Date().timeIntervalSince(node.start)
        let sample = LargePDFSample(
            metric: node.metric,
            duration: duration,
            context: node.context,
            timestamp: Date()
        )
        if #available(iOS 12.0, macOS 10.14, *) {
            os_signpost(.end, log: log, name: "LargePDF", "%{public}@", node.metric.rawValue)
        }
        recent.append(sample)
        if recent.count > maxSamples { recent.removeFirst(recent.count - maxSamples) }
    }

    /// Convenience wrapper that measures an async block.
    func measure<T>(_ metric: LargePDFMetric,
                    context: [String: String] = [:],
                    _ work: @escaping () async throws -> T) async rethrows -> T {
        let token = start(metric, context: context)
        defer { end(token) }
        return try await work()
    }

    /// Returns a quick summary of last N samples per metric (average duration).
    func summary() -> [LargePDFMetric: TimeInterval] {
        var bucket: [LargePDFMetric: [TimeInterval]] = [:]
        for s in recent {
            bucket[s.metric, default: []].append(s.duration)
        }
        var out: [LargePDFMetric: TimeInterval] = [:]
        for (k, arr) in bucket {
            guard !arr.isEmpty else { continue }
            out[k] = arr.reduce(0, +) / Double(arr.count)
        }
        return out
    }
}
