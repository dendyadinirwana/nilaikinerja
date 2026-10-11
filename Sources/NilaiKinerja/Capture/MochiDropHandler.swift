import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Handles drag-and-drop file ingestion directly onto Mochi or the notch capsule.
///
/// When files are dropped:
/// 1. Verifies supported file format (PDF, Word, Excel, Images).
/// 2. If unsupported: triggers .notchDropFailed (RobotHead in .error state with head shake & red X X eyes).
/// 3. If supported:
///    - Expands the panel to .home stage with the robot in scanning mode (.searching) for 1.5 seconds.
///    - Displays a "Memindai Berkas..." scanning badge.
///    - Once scanning completes (up to 2 seconds), automatically slides open the AddActivityForm
///      prefilled with the clean title, 1-hour time slot, and attached documents, while celebrating (.happy)!
@MainActor
enum MochiDropHandler {
    /// Allowed formats: all standard documents (PDF, Word, PPT/Presentation, Excel/Spreadsheet, Text) and Images.
    static let supportedExtensions: Set<String> = [
        // Documents
        "pdf",
        "docx", "doc", "rtf", "odt", "pages",
        "pptx", "ppt", "odp", "key",
        "xlsx", "xls", "csv", "ods", "numbers",
        "txt", "text", "md", "markdown",
        // Images
        "png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "svg", "tiff", "tif", "bmp", "ico"
    ]

    static func isSupported(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if supportedExtensions.contains(ext) { return true }
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) ||
               type.conforms(to: .presentation) ||
               type.conforms(to: .spreadsheet) ||
               type.conforms(to: .text) ||
               type.conforms(to: .pdf) ||
               type.conforms(to: .compositeContent) {
                return true
            }
        }
        return false
    }

    private static var lastDropTime: TimeInterval = 0

    @discardableResult
    static func handleDrop(
        urls: [URL],
        coordinator: TrackingCoordinator?,
        mode: PanelMode?,
        immediate: Bool = CommandLine.arguments.contains("--selftest")
    ) -> (success: Bool, title: String) {
        let nowStamp = CACurrentMediaTime()
        if !immediate {
            guard nowStamp - lastDropTime > 0.8 else { return (false, "") }
            lastDropTime = nowStamp
        }
        guard let firstURL = urls.first else { return (false, "") }

        // Reject if any dropped file is not PDF, Word, Excel, or an Image
        let unsupported = urls.filter { !isSupported(url: $0) }
        if !unsupported.isEmpty {
            let ext = unsupported.first?.pathExtension.isEmpty == false
                ? unsupported.first!.pathExtension.uppercased()
                : "FILE"
            let errorReason = "Format .\(ext) tidak didukung (Hanya Dokumen & Gambar)"

            mode?.isHomeFormOpen = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                mode?.screen = .home
            }
            // Open panel so user sees the robot head in error state with red pill
            NotificationCenter.default.post(name: .notchExpandPanel, object: nil)
            NotificationCenter.default.post(
                name: .notchDropFailed,
                object: nil,
                userInfo: ["reason": errorReason]
            )
            NSSound.beep()
            return (false, errorReason)
        }

        let cleanedTitle = cleanActivityTitle(from: firstURL)

        let populateForm = {
            let now = Date()
            let oneHourLater = now.addingTimeInterval(3600)

            mode?.prefillAddTitle = cleanedTitle
            mode?.prefillAddDetail = urls.count == 1
                ? "Dokumen pendukung dari berkas: \(firstURL.lastPathComponent)"
                : "Dokumen pendukung dari \(urls.count) berkas"
            mode?.prefillAddURLs = urls
            mode?.prefillAddFrom = now
            mode?.prefillAddTo = oneHourLater

            mode?.isHomeFormOpen = false
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                mode?.screen = .add
            }

            NotificationCenter.default.post(
                name: .notchDropCelebrated,
                object: nil,
                userInfo: ["title": cleanedTitle]
            )
            NSSound(named: "Glass")?.play()
        }

        if immediate {
            let validation = FileContentValidator.validate(url: firstURL)
            switch validation {
            case .invalid(let reason):
                NotificationCenter.default.post(name: .notchExpandPanel, object: nil)
                NotificationCenter.default.post(
                    name: .notchDropFailed,
                    object: nil,
                    userInfo: ["reason": reason]
                )
                NSSound.beep()
                return (false, reason)
            case .valid:
                NotificationCenter.default.post(name: .notchExpandPanel, object: nil)
                populateForm()
                return (true, cleanedTitle)
            }
        }

        // 1. Expand panel and stay on home stage (form closed) to display scanning mode
        mode?.isHomeFormOpen = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            mode?.screen = .home
        }
        NotificationCenter.default.post(name: .notchExpandPanel, object: nil)

        // 2. Post scanning notification so RobotHead switches to .searching state
        NotificationCenter.default.post(
            name: .notchDropScanning,
            object: nil,
            userInfo: [
                "filename": firstURL.lastPathComponent,
                "title": cleanedTitle
            ]
        )

        // 3. Perform REAL deep content validation during the 1.5s scanning window
        DispatchQueue.global(qos: .userInitiated).async {
            let validation = FileContentValidator.validate(url: firstURL)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                switch validation {
                case .invalid(let reason):
                    NotificationCenter.default.post(
                        name: .notchDropFailed,
                        object: nil,
                        userInfo: ["reason": reason]
                    )
                    NSSound.beep()
                case .valid(let format, _):
                    NKLog("[Validator] File verified genuine: \(format) for \(firstURL.lastPathComponent)")
                    populateForm()
                }
            }
        }

        return (true, cleanedTitle)
    }

    /// Derives a clean, professional ASN activity title from the dropped file's name.
    static func cleanActivityTitle(from url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        var cleaned = base
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = cleaned.lowercased()
        if lower.contains("screenshot") || lower.contains("tangkapan layar") {
            return "Dokumentasi & Bukti Kinerja"
        }

        if cleaned.isEmpty {
            return "Penyusunan Berkas & Dokumen Kinerja"
        }

        // If filename is all lowercase or all uppercase, capitalize words nicely
        if cleaned == lower || cleaned == cleaned.uppercased() {
            cleaned = cleaned.capitalized
        }

        if lower.hasPrefix("laporan") || lower.hasPrefix("telaah") || lower.hasPrefix("rekap") || lower.hasPrefix("nota") || lower.hasPrefix("draf") {
            return cleaned
        }

        return "Penyusunan berkas: \(cleaned)"
    }
}
