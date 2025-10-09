import SwiftUI
import Combine
import os.log

/// Central loading + progress coordinator used across the app.
/// - Provides a generic `startLoading/stopLoading` API with a typed reason (`LoadingType`)
/// - Exposes convenience helpers (PDF, search, file, web, monaco, export/import/backup/restore)
/// - Tracks multiple concurrent tasks so UI only hides once all are done.
/// - Publishes progress + message so views can show spinners/progress bars.
@MainActor
final class WebLoadingStateManager: ObservableObject {
    static let shared = WebLoadingStateManager()
    private init() {}

    // MARK: Published UI State
    /// Whether *any* loading task is active.
    @Published var isLoading: Bool = false

    /// User-facing message (short, friendly).
    @Published var loadingMessage: String = ""

    /// Optional 0...1 progress for long operations (0 = indeterminate).
    @Published var loadingProgress: Double = 0.0

    /// The most recent/loading "type" (used by buttons/overlays to theme or label).
    @Published var loadingType: LoadingType = .general

    // MARK: Internal tracking
    /// We key concurrent tasks by a stringified type so different features can overlap.
    private var activeTasks: Set<String> = []

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Prism",
                             category: "LoadingState")

    // MARK: Loading Type
    enum LoadingType: CustomStringConvertible {
        case general
        case pdf
        case search
        case file
        case monaco
        case web
        case export
        case `import`
        case backup
        case restore

        var description: String {
            switch self {
            case .general: return "General"
            case .pdf:     return "PDF"
            case .search:  return "Search"
            case .file:    return "File"
            case .monaco:  return "Monaco"
            case .web:     return "Web"
            case .export:  return "Export"
            case .import:  return "Import"
            case .backup:  return "Backup"
            case .restore: return "Restore"
            }
        }
    }

    // MARK: Core API

    /// Begin a loading task.
    /// - Parameters:
    ///   - type: area/feature (influences UI copy and theming)
    ///   - message: short description shown to the user
    ///   - progress: 0 means “indeterminate”. Use 0...1 for determinate bars.
    func startLoading(_ type: LoadingType, message: String, progress: Double = 0.0) {
        let key = keyFor(type)
        activeTasks.insert(key)

        isLoading = true
        loadingType = type
        loadingMessage = message
        loadingProgress = clamped(progress)

        log.info("Start loading (\(type.description, privacy: .public)): \(message, privacy: .public)")
    }

    /// Update progress and (optionally) the message/title.
    func updateProgress(_ progress: Double, message: String? = nil) {
        loadingProgress = clamped(progress)
        if let msg = message { loadingMessage = msg }
    }

    /// Finish a specific loading task.
    func stopLoading(_ type: LoadingType) {
        let key = keyFor(type)
        activeTasks.remove(key)

        log.info("Stop loading (\(type.description, privacy: .public))")

        if activeTasks.isEmpty {
            // Reset visible state
            isLoading = false
            loadingMessage = ""
            loadingProgress = 0.0
        } else {
            // Keep showing a loader if other tasks remain active.
            // We don't know which message is most relevant; keep current.
        }
    }

    /// Nuke all tasks & reset state (use with care).
    func stopAll() {
        activeTasks.removeAll()
        isLoading = false
        loadingMessage = ""
        loadingProgress = 0.0
        log.info("Stop all loading tasks")
    }

    // MARK: Convenience Helpers (compatibility with existing calls)

    // PDF
    func startPDFLoading(_ message: String = "Loading PDF…") {
        startLoading(.pdf, message: message)
    }
    func updatePDFProgress(_ progress: Double, message: String? = nil) {
        updateProgress(progress, message: message)
    }
    func stopPDFLoading() {
        stopLoading(.pdf)
    }

    // Search
    func startSearch(_ message: String = "Searching…") {
        startLoading(.search, message: message)
    }
    func stopSearch() {
        stopLoading(.search)
    }

    // File ops
    func startFileOperation(_ message: String = "Processing file…") {
        startLoading(.file, message: message)
    }
    func stopFileOperation() {
        stopLoading(.file)
    }

    // Monaco editor
    func startMonacoLoading(_ message: String = "Initializing editor…") {
        startLoading(.monaco, message: message)
    }
    func stopMonacoLoading() {
        stopLoading(.monaco)
    }

    // Web
    func startWebLoading(_ message: String = "Loading webpage…") {
        startLoading(.web, message: message)
    }
    func stopWebLoading() {
        stopLoading(.web)
    }

    // Export
    func startExport(_ message: String = "Exporting…") {
        startLoading(.export, message: message)
    }
    func updateExportProgress(_ progress: Double, message: String? = nil) {
        updateProgress(progress, message: message)
    }
    func stopExport() {
        stopLoading(.export)
    }

    // Import
    func startImport(_ message: String = "Importing…") {
        startLoading(.import, message: message)
    }
    func updateImportProgress(_ progress: Double, message: String? = nil) {
        updateProgress(progress, message: message)
    }
    func stopImport() {
        stopLoading(.import)
    }

    // Backup
    func startBackup(_ message: String = "Creating backup…") {
        startLoading(.backup, message: message)
    }
    func stopBackup() {
        stopLoading(.backup)
    }

    // Restore
    func startRestore(_ message: String = "Restoring…") {
        startLoading(.restore, message: message)
    }
    func stopRestore() {
        stopLoading(.restore)
    }

    // MARK: Helpers
    private func keyFor(_ type: LoadingType) -> String { String(describing: type) }
    private func clamped(_ value: Double) -> Double { min(1.0, max(0.0, value)) }
}
