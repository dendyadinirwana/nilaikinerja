import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set from the command line to pin the panel open for visual
    /// verification. `nil` in normal use — hover drives the panel instead.
    enum DemoMode { case home, expanded, checkpoint, addActivity, addPrefill, settings, swipeOpen, swipeLeap, capsule, chat, chatLive, chatThinking, mochiDrag }
    var demoMode: DemoMode?

    private let controller = NotchWindowController()
    private let bridge = WindowBridge()
    private var coordinator: TrackingCoordinator?
    private var statusItem: StatusItemController?
    private var screenObserver: NSObjectProtocol?
    private var demoTerminator: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock tile, no menu bar takeover. The notch capsule
        // and a status item are the entire UI.
        NSApp.setActivationPolicy(.accessory)

        let store = SessionStore()
        let coordinator = TrackingCoordinator(store: store)
        self.coordinator = coordinator

        guard let screen = NotchGeometry.preferredScreen() else {
            NSLog("[App] no screen available")
            return
        }
        let metrics = NotchGeometry.metrics(for: screen)
        bridge.geometry = metrics

        let root = RootView(
            coordinator: coordinator,
            windowModel: bridge,
            hover: bridge.hoverState,
            motion: bridge.notchMotion
        )
        controller.makeWindow(geometry: metrics, content: AnyView(root))
        bridge.bind(coordinator: coordinator, controller: controller)

        // The window controller owns the mouse monitors; it forwards the
        // resulting hover state into the shared object the view observes.
        controller.onHoverChange = { [weak self] over in
            self?.bridge.hoverState.setOver(over)
        }
        // Drag sessions never deliver mouse-moved events, so the panel is
        // opened from the drag callbacks instead. Without this the file is
        // released onto the desktop and macOS grows a Finder tile there.
        controller.onDragHover = { [weak self] dragging in
            self?.bridge.hoverState.setDrag(dragging)
        }
        // A cancelled drag must not leave the panel pinned open. Only a pin that
        // came from a drop is released; a menu-bar pin is deliberate and stays.
        controller.onDragCancelled = { [weak self] in
            self?.bridge.hoverState.releaseDropPin()
        }

        coordinator.start()

        let item = StatusItemController(coordinator: coordinator, controller: controller)
        item.install()
        statusItem = item

        observeDisplays()
        applyDemoMode()

        NSLog(
            "[App] launched — SkyLight: \(controller.isUsingSkyLight), "
            + "notch: \(Int(metrics.collapsed.width))x\(Int(metrics.collapsed.height)), "
            + "notched: \(metrics.isNotched)"
        )
    }

    /// Pins the panel open so the expanded layout can be inspected, and quits
    /// after 15 seconds so an automated screenshot run terminates on its own.
    private func applyDemoMode() {
        guard let demoMode else {
            runDiagnostics()
            return
        }
        if demoMode != .capsule {
            // Pin *after* a beat, not before the first frame. Setting it here means
            // `isExpanded` is already true when the panel is built, so there is no
            // transition to capture: the entrance cascade never fires and the
            // motion this mode exists to show is exactly the motion a screenshot
            // would miss. Holding it back a moment gives a real open to sample.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.bridge.hoverState.pinned = true
            }
        }
        if demoMode == .home {
            bridge.panelMode.screen = .home
        }
        if demoMode == .expanded {
            bridge.panelMode.screen = .list
        }
        if demoMode == .checkpoint {
            bridge.panelMode.screen = .checkpoint
        }
        if demoMode == .addActivity {
            bridge.panelMode.screen = .add
        }
        if demoMode == .addPrefill {
            let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("Laporan_Evaluasi_PPDT_2026.pdf")
            try? "PDF-DUMMY".data(using: .utf8)?.write(to: fixture)
            MochiDropHandler.handleDrop(urls: [fixture], coordinator: coordinator, mode: bridge.panelMode)
        }
        if demoMode == .settings {
            bridge.panelMode.screen = .settings
        }
        if demoMode == .chat {
            bridge.panelMode.screen = .chat
        }
        // `--demo-chat-live` also sends a real prompt once the view is up, so a
        // screenshot proves the whole path (key resolve -> stream -> render)
        // rather than just an empty composer.
        if demoMode == .chatLive {
            bridge.panelMode.screen = .chat
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let settings = AppSettings.shared
                AIChatService.shared.sendMessage(
                    "Berikan ringkasan 2 langkah verifikasi SIPPDT dalam format Markdown: ada heading sub-judul, bullet point dengan **kata tebal**, dan satu blok kode bash singkat.",
                    baseURL: settings.aiBaseURL,
                    storedKey: settings.aiApiKey,
                    model: settings.aiModel
                )
            }
        }
        if demoMode == .chatThinking {
            bridge.panelMode.screen = .chat
            AIChatService.shared.messages = [
                ChatMessage(role: .user, content: "Bantu buat draf laporan evaluasi"),
                ChatMessage(role: .assistant, content: "", isThinking: true)
            ]
        }
        if demoMode == .mochiDrag {
            bridge.panelMode.screen = .home
        }
        if demoMode == .swipeOpen {
            bridge.panelMode.demoSwipePose = "open"
        }
        if demoMode == .swipeLeap {
            bridge.panelMode.demoSwipePose = "leap"
        }

        // Let SwiftUI settle the spring before anyone screenshots, and log the
        // state so a failed demo run is diagnosable from the log alone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let state: String
            if self.coordinator?.panelState == .checkpoint { state = "checkpoint" }
            else if self.coordinator?.panelState == .paused { state = "paused" }
            else { state = "collapsed" }
            NSLog(
                "[Demo] pinned=\(self.bridge.hoverState.pinned) "
                + "expanded=\(self.bridge.hoverState.isExpanded) "
                + "state=\(state)"
            )
        }

        // `--hitdump` proves the click-through math instead of asserting it: it
        // reports the interactive rect the window is using and hit-tests the
        // actual header button centres, so a dead button shows up in the log
        // as a nil hit rather than as a shrug.
        if CommandLine.arguments.contains("--hitdump") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                self.dumpHitTest()
            }
        }

        // Long enough that a screenshot-and-measure cycle does not race the
        // teardown. Short enough that a forgotten demo run still cleans up.
        let terminator = Timer(timeInterval: 60, repeats: false) { _ in
            NSApp.terminate(nil)
        }
        RunLoop.main.add(terminator, forMode: .common)
        demoTerminator = terminator
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    /// Diagnostics that must run even without a demo mode, because they answer
    /// questions a still screenshot cannot: is the sprite actually advancing,
    /// and is the header actually hit-testable.
    /// Rasterises `ModelSelectorLabel` on the real notch background so the
    /// chevron's colour and contrast can be judged from pixels rather than
    /// inferred from `menuStyle` semantics.
    private func dumpModelSelectorLabel() {
        @MainActor
        func render() {
            // Side by side: the bare label rendered perfectly, so if the
            // Menu-wrapped copy comes out blank or untinted, the wrapper is
            // doing it and the fix belongs on `.menuStyle`.
            let settings = AppSettings.shared
            let view = VStack(alignment: .leading, spacing: 14) {
                ModelSelectorLabel(model: "gemini/gemini-3.8-flash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                ModelSelectorMenu(settings: settings, service: AIChatService.shared)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("^ bare label      v inside Menu")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(hex: 0x16181F))

            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 260, height: 110)
            host.layoutSubtreeIfNeeded()

            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: URL(fileURLWithPath: "/tmp/aipick.png"))
            NSLog("[Diag] wrote /tmp/aipick.png (\(rep.pixelsWide)x\(rep.pixelsHigh))")
        }
        MainActor.assumeIsolated { render() }
    }

    private func runDiagnostics() {
        if CommandLine.arguments.contains("--spritedump") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.dumpSpritePlayback()
            }
        }
        if CommandLine.arguments.contains("--hitdump") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                self.dumpHitTest()
            }
        }
        if CommandLine.arguments.contains("--mochidump") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.dumpMochiStates()
            }
        }
        if CommandLine.arguments.contains("--aipickdump") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.dumpModelSelectorLabel()
            }
        }
    }

    /// Renders every Mochi pose to a PNG sheet.
    ///
    /// The character is procedural, so "does it look like Mochi" cannot be
    /// checked by reading the code — it has to be rasterised and looked at. The
    /// pack that came before this renderer passed every load check while drawing
    /// entirely the wrong character, which is exactly the failure a render
    /// catches and a log line does not.
    private func dumpMochiStates() {
        let poses: [(MochiPose, MochiEmote?, String)] = [
            (.idle, nil, "idle"),
            (.working, nil, "working"),
            (.thinking, nil, "thinking"),
            (.searching, nil, "searching"),
            (.approval, .surprised, "approval"),
            (.question, nil, "question"),
            (.error, nil, "error"),
            (.finished, .proud, "finished"),
            (.ratelimit, nil, "ratelimit"),
            (.sleeping, nil, "sleeping"),
            (.dizzy, nil, "dizzy"),
        ]

        let cell: CGFloat = 120
        let cols = 4
        let rows = Int(ceil(Double(poses.count) / Double(cols)))
        let colsF: CGFloat = CGFloat(cols)
        let rowsF: CGFloat = CGFloat(rows)
        let sheet = HStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { r in
                VStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { c in
                        let i = r * cols + c
                        Group {
                            if i < poses.count {
                                MochiView(state: poses[i].0, emote: poses[i].1, side: cell,
                                          fixedLook: CGPoint(x: 0.2, y: 0.1))
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .frame(width: cell * colsF, height: cell * rowsF)
        .background(Color(red: 0.086, green: 0.094, blue: 0.122))

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        if let img = renderer.nsImage,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let path = "/tmp/mochi_states.png"
            try? png.write(to: URL(fileURLWithPath: path))
            NSLog("[MochiDump] wrote \(path) (\(poses.count) poses: \(poses.map { $0.2 }.joined(separator: ", ")))")
        } else {
            NSLog("[MochiDump] FAIL — could not rasterise")
        }
    }

    /// Drives a real `APNGPlaybackView` and logs the frame index over time.
    ///
    /// A pack that decodes but never steps looks identical to a working one in
    /// a still image, so this reports the numbers that actually distinguish
    /// them: total frames, frames advanced, and repaints.
    private func dumpSpritePlayback() {
        let pack = bridge.liveIcon
        let combos = pack.allCombos()
        NSLog("[Sprite] decoded combos: \(combos.count) — \(pack.loadReport)")

        guard let (voice, mood) = combos.first,
              let frames = pack.sprite(voice: voice, mood: mood) else {
            NSLog("[Sprite] FAIL — nothing decoded")
            return
        }
        NSLog("[Sprite] testing \(voice.rawValue)/\(mood.rawValue): frames=\(frames.count) loop=\(String(format: "%.2fs", frames.loopDuration))s")

        let view = APNGPlaybackView(frame: NSRect(x: 0, y: 0, width: 120, height: 120))
        view.setFrames(frames)
        view.start()

        let samples = 8
        for step in 1...samples {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.15) {
                NSLog("[Sprite] t=\(String(format: "%.2fs", Double(step) * 0.15)) frame=\(view.currentFrameIndex) repaints=\(view.repaintCount)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(samples) * 0.15 + 0.2) {
            view.stop()
            // Judge on the index, not the repaint count: this probe view is
            // deliberately never added to a window, so AppKit never calls draw
            // and repaints stays 0 even when the clock is stepping correctly.
            // A view that advanced past frame 0 is animating; one still on 0 is
            // the frame-zero failure this whole diagnostic exists to catch.
            let advanced = view.currentFrameIndex > 0
            let expected = max(1, Int(frames.loopDuration / frames.delays[0]))
            NSLog("[Sprite] VERDICT: \(advanced ? "ANIMATING" : "STUCK ON FRAME 0")"
                + " — advanced to frame \(view.currentFrameIndex)/\(frames.count)"
                + " (~frame \(expected) expected at this point in the loop, repaints=\(view.repaintCount) offscreen)")
        }
    }

    /// Logs whether each header button centre actually resolves to a hit-testable
    /// view. A nil result here is the exact symptom of "the button is visible
    /// but the click goes to the app underneath".
    private func dumpHitTest() {
        guard let panel = controller.panel,
              let window = panel as NSWindow?,
              let content = panel.contentView else { return }
        controller.forceInteractiveForDiagnostics()

        let screen = window.screen ?? NSScreen.main
        guard let screen else { return }
        let midX = screen.frame.midX
        let topY = screen.frame.maxY

        // Mirrors NotchHeaderBar: leading padding 12, 44pt buttons, 6pt gaps,
        // bar height = min(capsuleHeight, expandedChromeHeight - 60).
        let barHeight = min(
            CGFloat(bridge.settings.capsuleHeight),
            NotchGeometry.expandedChromeHeight - 60
        )
        let buttonY = topY - barHeight / 2
        let leftEdge = midX - CGFloat(bridge.settings.expandedWidth) / 2

        NSLog("[Hit] interactive=\(controller.interactiveRectDescription)")
        NSLog("[Hit] ignoresMouseEvents=\(panel.ignoresMouseEvents) isKey=\(panel.isKeyWindow)")
        NSLog("[Hit] window=\(NSStringFromRect(window.frame)) content=\(NSStringFromRect(content.frame))")
        NSLog("[Hit] expandedWidth=\(bridge.settings.expandedWidth) screen=\(NSStringFromRect(screen.frame))")

        // Grid probe: where does SwiftUI content actually accept a hit?
        var row = ""
        for step in 0..<12 {
            let y = topY - CGFloat(step) * 20
            var mark = " "
            for column in 0..<32 {
                let x = midX - 300 + CGFloat(column) * 20
                let p = window.convertPoint(fromScreen: NSPoint(x: x, y: y))
                mark += content.hitTest(p) == nil ? "." : "#"
            }
            row += "y-\(step * 20) \(mark)\n"
        }
        NSLog("[Hit] grid (# = hit-testable):\n\(row)")

        let tabs = ["home", "list", "chat", "add", "settings", "sound"]
        for (index, name) in tabs.enumerated() {
            let x: CGFloat
            if index < 4 {
                x = leftEdge + 12 + CGFloat(index) * 50 + 22
            } else {
                // Right cluster: 38pt buttons, 6pt gap, trailing padding 14.
                x = midX + CGFloat(bridge.settings.expandedWidth) / 2 - 14
                    - CGFloat(6 - index) * 44
            }
            let screenPoint = NSPoint(x: x, y: buttonY)
            let inWindow = window.convertPoint(fromScreen: screenPoint)
            let hit = content.hitTest(inWindow)
            NSLog(
                "[Hit] \(name) at (\(Int(x)),\(Int(buttonY))) -> "
                + "\(hit.map { String(describing: type(of: $0)) } ?? "NIL (click passes through)")"
            )
        }
    }

    /// Re-anchor the capsule when displays change. Without this, unplugging a
    /// monitor leaves the panel floating at a stale coordinate.
    private func observeDisplays() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NotificationCenter.default.post(name: .notchDisplayChanged, object: nil)
            }
        }
    }
}

/// SwiftUI's `App` protocol would own the main run loop, but this app needs
/// AppKit-first control over the window and activation policy, so the entry
/// point stays hand-written.
@main
struct NilaiKinerjaApp {
    static func main() {
        // `--selftest` exercises the data and report layers with no window and
        // no event loop, so a headless verification of the whole pipeline is
        // possible. It is the only way to check the .docx output without a
        // human clicking through the UI.
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            return
        }

        // `--selftest-ai` drives the real chat path (resolve key -> stream ->
        // collect) against the configured endpoint, so "chat works" can be
        // proven headlessly. A 401 here means the key, not the UI, is the
        // problem.
        if CommandLine.arguments.contains("--selftest-ai") {
            let settings = AppSettings.shared
            let service = AIChatService.shared
            service.sendMessage(
                "Balas persis satu kata: SIAP",
                baseURL: settings.aiBaseURL,
                storedKey: settings.aiApiKey,
                model: settings.aiModel
            )
            // AIChatService is @MainActor, so the main run loop has to keep
            // turning — blocking it on a semaphore would deadlock the driver.
            let deadline = Date().addingTimeInterval(150)
            while service.isStreaming && service.errorMessage == nil && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
            }
            let reply = service.messages.last(where: { $0.role == .assistant })?.content ?? ""
            let ok = service.errorMessage == nil && !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            print(ok ? "PASS — chat AI: \(reply.prefix(80))" : "FAIL — chat AI: \(service.errorMessage ?? "balasan kosong")")
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()

        // An uncaught ObjC exception (typically a SwiftUI assertion) turns
        // into SIGTRAP via `_crashOnException`, and the .ips file records no
        // reason. Logging it here is the only way to see what SwiftUI
        // actually complained about.
        NSSetUncaughtExceptionHandler { exception in
            NSLog("[Uncaught] %@: %@", exception.name.rawValue, exception.reason ?? "no reason")
            exception.callStackSymbols.forEach { NSLog("  %@", $0) }
        }

        // `--demo-expanded` force-pins the panel open for 12 seconds, which
        // lets the expanded layout be screenshot-verified without a human
        // hovering. `--demo-checkpoint` does the same in form mode. Must be
        // set before `run()` — that call blocks.
        if CommandLine.arguments.contains("--demo-home") {
            delegate.demoMode = .home
        } else if CommandLine.arguments.contains("--demo-expanded") {
            delegate.demoMode = .expanded
        } else if CommandLine.arguments.contains("--demo-checkpoint") {
            delegate.demoMode = .checkpoint
        } else if CommandLine.arguments.contains("--demo-add-prefill") {
            delegate.demoMode = .addPrefill
        } else if CommandLine.arguments.contains("--demo-add-activity") || CommandLine.arguments.contains("--demo-add") {
            delegate.demoMode = .addActivity
        } else if CommandLine.arguments.contains("--demo-mochi-drag") {
            delegate.demoMode = .mochiDrag
        } else if CommandLine.arguments.contains("--demo-settings") {
            delegate.demoMode = .settings
        } else if CommandLine.arguments.contains("--demo-chat-thinking") {
            delegate.demoMode = .chatThinking
        } else if CommandLine.arguments.contains("--demo-chat-live") {
            delegate.demoMode = .chatLive
        } else if CommandLine.arguments.contains("--demo-chat") {
            delegate.demoMode = .chat
        } else if CommandLine.arguments.contains("--demo-swipe-open") {
            delegate.demoMode = .swipeOpen
        } else if CommandLine.arguments.contains("--demo-swipe-leap") {
            delegate.demoMode = .swipeLeap
        } else if CommandLine.arguments.contains("--demo-capsule") {
            delegate.demoMode = .capsule
        }

        app.delegate = delegate
        app.run()
    }
}
