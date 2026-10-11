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
        registerForDraggedTypes([.fileURL, .init("NSFilenamesPboardType")])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .init("NSFilenamesPboardType")])
    }

    /// Highlight the drop target while a drag is over it, so it is obvious
    /// that the area accepts files.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = Self.urls(from: sender)
        guard !urls.isEmpty else { return [] }
        NSLog("[DropView] draggingEntered: \(urls.count) file(s)")
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
        NSLog("[DropView] performDragOperation accepted \(urls.count) file(s)")
        NotificationCenter.default.post(name: .notchFilesDelivered, object: nil)
        onDrop?(urls)
        return true
    }

    /// Accepts images and documents (PDF, Word, Excel, PowerPoint, Text, etc.).
    /// Filters out directories and ensures files exist on disk.
    static func urls(from sender: NSDraggingInfo) -> [URL] {
        var result: [URL] = []
        let pboard = sender.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            result.append(contentsOf: urls)
        }
        if result.isEmpty, let items = pboard.pasteboardItems {
            for item in items {
                if let str = item.string(forType: .fileURL), let u = URL(string: str) {
                    result.append(u)
                }
            }
        }
        if result.isEmpty, let filenames = pboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] {
            result.append(contentsOf: filenames.map { URL(fileURLWithPath: $0) })
        }

        return result.filter { url in
            guard url.isFileURL && !url.hasDirectoryPath else { return false }
            return !url.pathExtension.isEmpty
        }
    }
}
