import Foundation
import AppKit
import SwiftUI

/// Handles drag-and-drop file ingestion directly onto Mochi or the notch capsule.
///
/// When files are dropped, opens the "Tambah kegiatan" screen with:
/// - Activity title derived cleanly from the filename
/// - Time range defaulting to current time with 1 hour duration
/// - Dropped files pre-attached to the activity draft
/// - Automatic panel expansion so the user can immediately review and save.
@MainActor
enum MochiDropHandler {
    @discardableResult
    static func handleDrop(
        urls: [URL],
        coordinator: TrackingCoordinator?,
        mode: PanelMode?
    ) -> (success: Bool, title: String) {
        guard let firstURL = urls.first else { return (false, "") }

        let cleanedTitle = cleanActivityTitle(from: firstURL)

        // Standard time assumption: current time with 1 hour duration
        let now = Date()
        let oneHourLater = now.addingTimeInterval(3600)

        // Set prefill data on panelMode so AddActivityForm opens populated
        mode?.prefillAddTitle = cleanedTitle
        mode?.prefillAddDetail = urls.count == 1
            ? "Dokumen pendukung dari berkas: \(firstURL.lastPathComponent)"
            : "Dokumen pendukung dari \(urls.count) berkas"
        mode?.prefillAddURLs = urls
        mode?.prefillAddFrom = now
        mode?.prefillAddTo = oneHourLater

        // Keep on .home screen and trigger the inline activity form with Mochi companion
        mode?.isHomeFormOpen = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            mode?.screen = .home
        }

        // Expand the notch panel so user sees Mochi and the form immediately
        NotificationCenter.default.post(name: .notchExpandPanel, object: nil)
        NSSound(named: "Glass")?.play()

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
