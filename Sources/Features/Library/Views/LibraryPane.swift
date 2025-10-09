import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DocumentPicker: NSViewControllerRepresentable {
    var allowedContentTypes: [UTType] = [.pdf]
    var allowsMultipleSelection: Bool = false
    var canChooseDirectories: Bool = false
    var onPick: ([URL]) -> Void

    func makeNSViewController(context: Context) -> NSViewController {
        let vc = NSViewController()
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = allowsMultipleSelection
            panel.canChooseFiles = true
            panel.canChooseDirectories = canChooseDirectories

            // Use allowedContentTypes when available; otherwise fallback to filename extensions
            if #available(macOS 11.0, *) {
                if !allowedContentTypes.isEmpty {
                    panel.allowedContentTypes = allowedContentTypes
                }
            } else {
                // Fallback: derive common extensions from UTTypes
                let exts = allowedContentTypes.compactMap { $0.preferredFilenameExtension }
                if !exts.isEmpty { panel.allowedFileTypes = exts }
            }

            panel.begin { resp in
                onPick(resp == .OK ? panel.urls : [])
            }
        }
        return vc
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
