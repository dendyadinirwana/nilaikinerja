import AppKit
import SwiftUI

/// Menu-bar entry point. The panel itself is the primary surface, but a menu
/// item is how the user reaches the reports, the idle threshold, and Quit
/// without clicking into the notch.
///
/// `@MainActor` because every value it reads lives on the main actor, and
/// `NSMenuDelegate` callbacks are not main-actor-isolated by default.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private unowned let coordinator: TrackingCoordinator
    private unowned let controller: NotchWindowController

    init(coordinator: TrackingCoordinator, controller: NotchWindowController) {
        self.coordinator = coordinator
        self.controller = controller
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "clock.badge.checkmark",
            accessibilityDescription: "Nilai Kinerja"
        )
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuild(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let elapsed = NSMenuItem(
            title: "Berjalan \(coordinator.elapsedLabel)",
            action: nil, keyEquivalent: ""
        )
        elapsed.isEnabled = false
        menu.addItem(elapsed)

        if let reason = coordinator.pausedReason {
            let paused = NSMenuItem(title: reason.display, action: nil, keyEquivalent: "")
            paused.isEnabled = false
            menu.addItem(paused)
        }

        menu.addItem(.separator())

        let showItem = NSMenuItem(
            title: "Buka Rekap",
            action: #selector(togglePanel), keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let toggleTimer = NSMenuItem(
            title: "Jeda / Lanjutkan Timer",
            action: #selector(toggleTimer), keyEquivalent: ""
        )
        toggleTimer.target = self
        menu.addItem(toggleTimer)

        menu.addItem(.separator())

        let daily = NSMenuItem(
            title: "Ekspor Rekap Harian…",
            action: #selector(exportDaily), keyEquivalent: ""
        )
        daily.target = self
        menu.addItem(daily)

        let monthly = NSMenuItem(
            title: "Ekspor Rekap Bulanan…",
            action: #selector(exportMonthly), keyEquivalent: ""
        )
        monthly.target = self
        menu.addItem(monthly)

        let openFolder = NSMenuItem(
            title: "Buka Folder Hasil",
            action: #selector(openFolder), keyEquivalent: ""
        )
        openFolder.target = self
        menu.addItem(openFolder)

        menu.addItem(.separator())

        let diagnostic = NSMenuItem(
            title: "Status Render: \(controller.isUsingSkyLight ? "SkyLight" : "Fallback")",
            action: nil, keyEquivalent: ""
        )
        diagnostic.isEnabled = false
        menu.addItem(diagnostic)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Keluar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func togglePanel() {
        NotificationCenter.default.post(name: .notchTogglePanel, object: nil)
    }

    @objc private func toggleTimer() {
        MainActor.assumeIsolated { coordinator.togglePause() }
    }

    @objc private func exportDaily() {
        MainActor.assumeIsolated {
            do {
                let url = try coordinator.exportDaily()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSLog("[Report] daily export failed: \(error)")
                NSSound.beep()
            }
        }
    }

    @objc private func exportMonthly() {
        MainActor.assumeIsolated {
            do {
                let url = try coordinator.exportMonthly()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSLog("[Report] monthly export failed: \(error)")
                NSSound.beep()
            }
        }
    }

    @objc private func openFolder() {
        MainActor.assumeIsolated {
            NSWorkspace.shared.activateFileViewerSelecting(
                [ReportBuilder.defaultExportDirectory()]
            )
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let notchTogglePanel = Notification.Name("id.simbang.notch.togglePanel")
    static let notchCollapsePanel = Notification.Name("id.simbang.notch.collapsePanel")
    static let notchExpandPanel = Notification.Name("id.simbang.notch.expandPanel")
    static let notchDisplayChanged = Notification.Name("id.simbang.notch.displayChanged")
    static let notchCelebrate = Notification.Name("id.simbang.notch.celebrate")
    /// Posted by the hosting view when files are released anywhere on the
    /// notch canvas, so the drop opens the add-activity form with the files
    /// attached.
    static let notchDroppedFiles = Notification.Name("id.simbang.notch.droppedFiles")
    static let notchDropCelebrated = Notification.Name("id.simbang.notch.dropCelebrated")
    static let notchDragHoverChanged = Notification.Name("id.simbang.notch.dragHoverChanged")
    static let notchFilesDelivered = Notification.Name("id.simbang.notch.filesDelivered")
}
