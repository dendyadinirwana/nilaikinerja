import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Accepts documents and images dropped onto the notch panel or Mochi stage.
///
/// Uses an NSViewRepresentable rather than SwiftUI's `.onDrop`, because the
/// panel window is non-activating: SwiftUI's drop handling depends on the
/// hosting view being in the responder chain, which it is not while the app
/// runs as an accessory without ever taking focus.
struct AttachmentDropView: NSViewRepresentable {
    var onHover: ((Bool) -> Void)? = nil
    var onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.onHover = onHover
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        nsView.onHover = onHover
        nsView.onDrop = onDrop
    }
}

final class DropView: NSView {
    var onHover: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    /// Highlight the drop target while a drag is over it, so it is obvious
    /// that the area accepts files.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = Self.urls(from: sender)
        guard !urls.isEmpty else { return [] }
        onHover?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = Self.urls(from: sender)
        guard !urls.isEmpty else { return [] }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHover?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onHover?(false)
        let urls = Self.urls(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    /// Accepts images and documents (PDF, Word, Excel, PowerPoint, Text, etc.).
    /// Filters out directories and ensures files exist on disk.
    static func urls(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] else { return [] }

        return urls.filter { url in
            guard url.isFileURL && !url.hasDirectoryPath else { return false }
            // Accept any regular file or valid UTType
            if let type = UTType(filenameExtension: url.pathExtension.lowercased()) {
                if type.conforms(to: .item) || type.conforms(to: .content) || type.conforms(to: .data) {
                    return true
                }
            }
            return !url.pathExtension.isEmpty
        }
    }
}
