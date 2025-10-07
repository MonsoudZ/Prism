import os.log
enum Log {
    private static let logger = Logger(subsystem: "com.yourco.prism", category: "app")
    static func info(_ msg: String) { logger.info("\(msg, privacy: .public)") }
    static func error(_ msg: String) { logger.error("\(msg, privacy: .public)") }
}
