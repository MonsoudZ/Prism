//
//  Logging.swift
//  Prism (macOS)
//
//  Lightweight logging facade around os.Logger with categories + signposts.
//
import Foundation
import os.log
import os.signpost

// MARK: - Public Facade (macOS)

enum Log {
    // Default app logger
    private static let app = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yourco.prism",
        category: "app"
    )

    // Common categories
    static let ui      = Category("ui")
    static let pdf     = Category("pdf")
    static let notes   = Category("notes")
    static let library = Category("library")
    static let network = Category("network")
    static let perf    = Category("perf")
    static let persist = Category("persistence")

    // --- Simple one-liners ---
    static func info(_ msg: String,
                     file: StaticString = #fileID,
                     function: StaticString = #function,
                     line: UInt = #line) {
        app.info("\(prefix(file,function,line)) \(msg, privacy: .public)")
    }

    static func error(_ msg: String,
                      file: StaticString = #fileID,
                      function: StaticString = #function,
                      line: UInt = #line) {
        app.error("\(prefix(file,function,line)) \(msg, privacy: .public)")
    }

    static func debug(_ msg: String,
                      file: StaticString = #fileID,
                      function: StaticString = #function,
                      line: UInt = #line) {
        #if DEBUG
        app.debug("\(prefix(file,function,line)) \(msg, privacy: .public)")
        #endif
    }

    static func warning(_ msg: String,
                        file: StaticString = #fileID,
                        function: StaticString = #function,
                        line: UInt = #line) {
        app.log(level: .default, "\(prefix(file,function,line)) ⚠️ \(msg, privacy: .public)")
    }

    static func fault(_ msg: String,
                      file: StaticString = #fileID,
                      function: StaticString = #function,
                      line: UInt = #line) {
        app.fault("\(prefix(file,function,line)) \(msg, privacy: .public)")
    }

    // MARK: - Category wrapper

    struct Category {
        private let logger: Logger
        private let oslog: OSLog  // required for signposts

        init(_ name: String,
             subsystem: String = Bundle.main.bundleIdentifier ?? "com.yourco.prism") {
            self.logger = Logger(subsystem: subsystem, category: name)
            self.oslog  = OSLog(subsystem: subsystem, category: name)
        }

        func info(_ msg: String,
                  file: StaticString = #fileID,
                  function: StaticString = #function,
                  line: UInt = #line) {
            logger.info("\(prefix(file,function,line)) \(msg, privacy: .public)")
        }

        func debug(_ msg: String,
                   file: StaticString = #fileID,
                   function: StaticString = #function,
                   line: UInt = #line) {
            #if DEBUG
            logger.debug("\(prefix(file,function,line)) \(msg, privacy: .public)")
            #endif
        }

        func warning(_ msg: String,
                     file: StaticString = #fileID,
                     function: StaticString = #function,
                     line: UInt = #line) {
            logger.log(level: .default, "\(prefix(file,function,line)) ⚠️ \(msg, privacy: .public)")
        }

        func error(_ msg: String,
                   file: StaticString = #fileID,
                   function: StaticString = #function,
                   line: UInt = #line) {
            logger.error("\(prefix(file,function,line)) \(msg, privacy: .public)")
        }

        func fault(_ msg: String,
                   file: StaticString = #fileID,
                   function: StaticString = #function,
                   line: UInt = #line) {
            logger.fault("\(prefix(file,function,line)) \(msg, privacy: .public)")
        }

        // MARK: Signposts (macOS 10.14+)

        @discardableResult
        func signpostBegin(_ id: StaticString,
                           _ message: String = "",
                           file: StaticString = #fileID,
                           function: StaticString = #function,
                           line: UInt = #line) -> OSSignpostID {
            guard #available(macOS 10.14, *) else { return .invalid }
            let sp = OSSignpostID(log: oslog)
            os_signpost(.begin, log: oslog, name: id, signpostID: sp,
                        "%{public}@ %{public}@", "\(prefix(file,function,line))", message)
            return sp
        }

        func signpostEnd(_ id: StaticString,
                         signpostID: OSSignpostID,
                         _ message: String = "",
                         file: StaticString = #fileID,
                         function: StaticString = #function,
                         line: UInt = #line) {
            guard #available(macOS 10.14, *), signpostID != .invalid else { return }
            os_signpost(.end, log: oslog, name: id, signpostID: signpostID,
                        "%{public}@ %{public}@", "\(prefix(file,function,line))", message)
        }

        /// Time a closure; emits signposts + a summary log.
        func time<T>(_ name: StaticString,
                     _ message: String = "",
                     file: StaticString = #fileID,
                     function: StaticString = #function,
                     line: UInt = #line,
                     do work: () -> T) -> T {
            let sp = signpostBegin(name, message, file: file, function: function, line: line)
            let start = Date()
            let result = work()
            let ms = (Date().timeIntervalSince(start) * 1000).rounded()
            signpostEnd(name, signpostID: sp, "\(message) took \(ms)ms", file: file, function: function, line: line)
            logger.info("\(prefix(file,function,line)) \(name) \(message, privacy: .public) took \(ms, privacy: .public)ms")
            return result
        }
    }

    // MARK: - Shared prefix (thread + source location)

    private static func prefix(_ file: StaticString,
                               _ function: StaticString,
                               _ line: UInt) -> String {
        let thread = Thread.isMainThread ? "main" : (Thread.current.name ?? "bg")
        return "[\(thread)] \(file):\(line) \(function)"
    }
}
