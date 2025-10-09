import SwiftUI
import Combine
import os.log

@MainActor
final class LoadingStateManager: ObservableObject {
    static let shared = LoadingStateManager()

    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var loadingProgress: Double = 0.0
    @Published var loadingType: LoadingType = .general

    private var tokens: Set<String> = []

    enum LoadingType {
        case general, pdf, search, file, monaco, web, sketch, export, `import`, backup, restore
    }

    private init() {}

    func startLoading(_ type: LoadingType, message: String, progress: Double = 0.0) {
        let id = "\(type)"
        tokens.insert(id)
        isLoading = true
        loadingType = type
        loadingMessage = message
        loadingProgress = progress
        Logger(subsystem: "Prism", category: "Loading").info("Start \(String(describing: type)): \(message)")
    }

    func updateProgress(_ progress: Double, message: String? = nil) {
        loadingProgress = progress
        if let m = message { loadingMessage = m }
    }

    func stopLoading(_ type: LoadingType) {
        let id = "\(type)"
        tokens.remove(id)
        if tokens.isEmpty {
            isLoading = false
            loadingMessage = ""
            loadingProgress = 0.0
        }
    }

    func stopAll() {
        tokens.removeAll()
        isLoading = false
        loadingMessage = ""
        loadingProgress = 0.0
    }

    // Convenience groups used in your panes
    func startPDFLoading(_ m: String = "Loading PDF…") { startLoading(.pdf, message: m) }
    func stopPDFLoading() { stopLoading(.pdf) }
    func startSearch(_ m: String = "Searching…") { startLoading(.search, message: m) }
    func stopSearch() { stopLoading(.search) }
    func startFileOperation(_ m: String = "Working on files…") { startLoading(.file, message: m) }
    func stopFileOperation() { stopLoading(.file) }
    func startMonacoLoading(_ m: String = "Initializing editor…") { startLoading(.monaco, message: m) }
    func stopMonacoLoading() { stopLoading(.monaco) }
    func startWebLoading(_ m: String = "Loading webpage…") { startLoading(.web, message: m) }
    func stopWebLoading() { stopLoading(.web) }
}

/// Simple overlay you can drop at the top of windows
struct LoadingOverlay: View {
    @ObservedObject var loading = LoadingStateManager.shared
    var body: some View {
        if loading.isLoading {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(loading.loadingMessage).foregroundStyle(.secondary)
                    if loading.loadingProgress > 0 {
                        ProgressView(value: loading.loadingProgress).frame(width: 220)
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 12)
            }
            .transition(.opacity)
        }
    }
}
