import AppKit
import SwiftUI

/// The borderless panel that lives in the notch.
@MainActor
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that rejects hit tests outside the active notch shape,
/// ensuring clicks outside the interactive area pass through cleanly.
@MainActor
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var isPointInteractive: ((NSPoint) -> Bool)?
    var isDragArmed = false

    var onDragHover: ((Bool) -> Void)?
    var onDropURLs: (([URL]) -> Void)?
    var onDropDelivered: (() -> Void)?

    @MainActor required dynamic init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL, .init("NSFilenamesPboardType")])
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        registerForDraggedTypes([.fileURL, .init("NSFilenamesPboardType")])
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // While a drag is in flight, if a specific drop destination (like a
        // dashed attachment box inside a form) claims the point, yield to it.
        // Otherwise, claim the point for this hosting view so general notch drops
        // land here instead of the Finder Desktop underneath.
        if isDragArmed {
            if let hit = super.hitTest(point), hit !== self, hit is DropView {
                return hit
            }
            return self
        }

        guard let isPointInteractive else { return super.hitTest(point) }
        // The point arrives in the superview's coordinates. Treating it as
        // local — which an earlier version of this method did — made the gate
        // reject almost everything, which is what left the header buttons
        // unclickable.
        let inSelf = convert(point, from: superview)
        let inWindow = convert(inSelf, to: nil)
        guard let window else { return nil }
        let screenPoint = window.convertPoint(toScreen: inWindow)
        if !isPointInteractive(screenPoint) {
            return nil
        }
        return super.hitTest(point)
    }

    private static func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        var result: [URL] = []
        let pboard = sender.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let objects = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            result.append(contentsOf: objects)
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
        return result.filter { $0.isFileURL && !$0.hasDirectoryPath }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragHover?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragHover?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragHover?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragHover?(false)
        let urls = Self.fileURLs(from: sender)
        guard !urls.isEmpty else {
            NSLog("[Drag] performDragOperation — no file URLs on pasteboard")
            return false
        }
        NSLog("[Drag] performDragOperation — accepted \(urls.count) file(s): \(urls.map { $0.lastPathComponent }.joined(separator: ", "))")
        onDropDelivered?()
        NotificationCenter.default.post(name: .notchFilesDelivered, object: nil)
        onDropURLs?(urls)
        return true
    }

    /// Bypasses the interactive-rect gate and asks AppKit directly. Used by the
    /// `--hitdump` diagnostic to tell "the gate rejected it" apart from
    /// "SwiftUI has no view there", which look identical from the outside.
    func rawHitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point)
    }

    /// Crucial for accessory notch apps: ensures clicks from background or other
    /// apps immediately trigger buttons on the FIRST click without requiring
    /// an initial click just to activate the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

/// Owns the window and keeps it glued to the notch.
///
/// The window frame never changes after creation. The notch shape animates
/// What the drag watch should do for one polled sample.
///
/// Split out as a pure function of (button state, pointer location) so the
/// transitions can be asserted directly. The bug this guards against was not
/// visible in any build output or log: a panel that only opened for a drag when
/// AppKit happened to deliver `draggingEntered`, which it does not do for a
/// window that is click-through. Asserting the decision table is the only way
/// to know the collapsed case is covered.
enum DragDecision: Equatable {
    /// Nothing to do: no button held, or the pointer is elsewhere and we are
    /// not holding the panel open.
    case none
    /// The left button just went down anywhere on screen — a drag has started.
    case dragBegan
    /// Pointer is over the notch with the button down — take the panel.
    case enterZone
    /// Already holding the panel open for this drag; just keep it open.
    case holdOpen
    /// Button is down but the pointer left the zone — an aborted drag.
    case leaveZone
    /// The button was released since the last poll — the drag ended.
    case dragEnded
}

func dragDecision(
    leftDown: Bool,
    wasDown: Bool,
    holdingOpen: Bool,
    location: NSPoint,
    zone: NSRect
) -> DragDecision {
    // A released button ends the session regardless of where the pointer is.
    // Checked first so a drag that ends outside the zone still tears down.
    if wasDown && !leftDown { return .dragEnded }
    guard leftDown else { return .none }

    // Arm the moment the drag starts, wherever the pointer is. AppKit builds
    // its drag-destination candidate list when the session begins: a window
    // that is `ignoresMouseEvents = true` at that instant is left out of the
    // list entirely. Flipping it later — when the pointer is already over the
    // notch — is too late, because the routing for that session is already
    // settled, so the file is released onto the desktop and macOS grows a
    // Finder tile. Arming early puts the window in the running.
    if !wasDown { return .dragBegan }

    if !NSMouseInRect(location, zone, false) {
        return holdingOpen ? .leaveZone : .none
    }
    return holdingOpen ? .holdOpen : .enterZone
}

/// inside a fixed canvas, so the expansion is a real spring interpolation
/// rather than an AppKit window resize (which snaps).
@MainActor
final class NotchWindowController: NSObject {
    private(set) var panel: NotchPanel?
    private var metrics: NotchGeometry.Metrics?
    private var usingSkyLight = false
    private var mouseMonitor: Any?
    private var globalMonitor: Any?
    private var dragBeginMonitor: Any?
    private var dragMoveMonitor: Any?
    private var dragEndMonitor: Any?
    private var dragWatchTimer: Timer?

    /// Current interactive rect in screen coordinates. The panel ignores
    /// mouse events outside it, so clicks reach the app underneath — a
    /// 1000pt canvas that swallowed input everywhere would be unusable.
    private var interactiveRect: NSRect = .zero

    /// Set NK_DEBUG_HIT=1 to trace every gate decision (hover region, presented
    /// size, ignoresMouseEvents). Dead clicks are invisible from the outside —
    /// the button is drawn, the shortcut works, and the click simply lands on
    /// the app underneath — so the only honest way to fix them is to log the
    /// gate that rejected the point.
    private var tracesHitTest = ProcessInfo.processInfo.environment["NK_DEBUG_HIT"] == "1"

    private func trace(_ message: String) {
        guard tracesHitTest else { return }
        NKLog("[Hit] \(message) rect=\(interactiveRectDescription) ignores=\(panel?.ignoresMouseEvents ?? false)")
    }

    /// The size the SwiftUI surface is actually presenting right now. Fed by
    /// the view layer, because only it knows the real width (a user setting)
    /// and height (per screen) of the shape on screen.
    private var presentedSize: CGSize = .zero
    private var presentedExpanded = false

    /// Debounce so that moving the mouse out of the panel and immediately back
    /// does not cause a collapse/expand flicker.
    private var collapseWorkItem: DispatchWorkItem?

    /// Fires when the pointer enters or leaves the interactive region.
    var onHoverChange: ((Bool) -> Void)?

    /// Called when a drag hovers the notch so the surface can open before the
    /// file is released.
    var onDragHover: ((Bool) -> Void)?
    /// Fired when a drag ends without any files reaching the app.
    var onDragCancelled: (() -> Void)?

    /// How long the pointer must hover before expanding, and how long outside
    /// before collapsing. Synchronized with AppSettings.
    var openDelay: TimeInterval = 0.12
    var collapseDelay: TimeInterval = 0.25

    private var openWorkItem: DispatchWorkItem?

    func makeWindow(geometry: NotchGeometry.Metrics, content: AnyView) {
        let panel = NotchPanel(
            contentRect: NotchGeometry.canvasFrame(on: geometry.screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary
        ]
        let hostingView = NotchHostingView(rootView: content)
        hostingView.isPointInteractive = { [weak self] screenPoint in
            guard let self else { return false }
            return NSMouseInRect(screenPoint, self.interactiveRect, false)
        }
        mirrorDragArmed = { [weak hostingView] armed in
            hostingView?.isDragArmed = armed
        }
        hostingView.onDragHover = { [weak self] hovering in
            guard let self else { return }
            if hovering {
                self.handleDragHover(NSEvent.mouseLocation)
            } else {
                self.onDragHover?(false)
            }
        }
        hostingView.onDropDelivered = { [weak self] in
            self?.noteDragDeliveredFiles()
        }
        NotificationCenter.default.addObserver(
            forName: .notchFilesDelivered,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.noteDragDeliveredFiles()
            }
        }
        hostingView.onDropURLs = { urls in
            NotificationCenter.default.post(
                name: .notchDroppedFiles,
                object: nil,
                userInfo: ["urls": urls]
            )
        }
        panel.contentView = hostingView
        panel.delegate = self
        panel.registerForDraggedTypes([.fileURL])
        // By default, ignore mouse events across the large canvas so all clicks
        // reach whatever application or desktop is underneath.
        panel.ignoresMouseEvents = true

        self.panel = panel
        self.metrics = geometry
        self.presentedSize = geometry.collapsed
        self.presentedExpanded = false
        self.interactiveRect = NotchGeometry.presentedFrame(
            on: geometry.screen, size: geometry.collapsed
        )

        usingSkyLight = SkyLightBridge.shared.attach(panel)
        if !usingSkyLight {
            NSLog("[Notch] SkyLight unavailable, using statusBar level")
        }

        // Two monitors are needed: the global one fires while another app is
        // frontmost, the local one while our own panel has focus (which is
        // the case as soon as the user clicks into the text field).
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited]) { [weak self] event in
            MainActor.assumeIsolated { self?.evaluateHover(at: NSEvent.mouseLocation) }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluateHover(at: NSEvent.mouseLocation) }
        }

        // Drag arming runs on global button monitors, not on the poll timer.
        //
        // The timer is the wrong tool here and was the reason drop kept landing
        // on the desktop. This app is a background accessory: while a file is
        // being dragged out of Finder, *Finder* is the frontmost app, and macOS
        // throttles a background app's timers hard enough that a 60 ms poll can
        // go seconds between fires. By then the drag session has already picked
        // its destinations and this window was never in the list, so the file
        // was released onto the Desktop. Global monitors are delivered on every
        // event regardless of who is frontmost, so arming happens on the press
        // itself.
        dragBeginMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.armForDrag() }
        }
        dragMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollForDrag() }
        }
        dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollForDrag() }
        }

        panel.orderFrontRegardless()
        startDragWatch()
    }

    deinit {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let dragBeginMonitor { NSEvent.removeMonitor(dragBeginMonitor) }
        if let dragMoveMonitor { NSEvent.removeMonitor(dragMoveMonitor) }
        if let dragEndMonitor { NSEvent.removeMonitor(dragEndMonitor) }
        dragWatchTimer?.invalidate()
    }

    // MARK: - Drag watch

    /// Makes the window a live drop destination the instant a drag starts.
    ///
    /// Split out from the poll so the global `.leftMouseDown` monitor can arm
    /// immediately — that event is the only signal that arrives on time while
    /// another app is frontmost.
    private func armForDrag() {
        guard !dragArmed else { return }
        dragArmed = true
        dragButtonWasDown = true
        dragDeliveredFiles = false
        // Both halves are required. `ignoresMouseEvents` keeps the window out of
        // the drag session's candidate list; `isDragArmed` makes `hitTest`
        // answer for this view instead of declining via the click-through gate.
        // Setting only the first is what left 23 arm events and zero drops.
        mirrorDragArmed?(true)
        if panel?.ignoresMouseEvents == true {
            panel?.ignoresMouseEvents = false
        }
        NKLog("[Drag] began — window armed as drop destination")
    }

    /// A window with `ignoresMouseEvents = true` receives no drag events at
    /// all, so the file would be released on whatever sits underneath — which
    /// is how a dropped file ended up as a Finder tile on the desktop instead
    /// of opening the panel. Dragging also suppresses mouse-moved events, so
    /// the hover monitors cannot notice it; this poll reads the pressed-button
    /// mask instead and hands input back to the panel while a drag is over it.
    private func startDragWatch() {
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollForDrag() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragWatchTimer = timer
    }

    // NSEvent.pressedMouseButtons uses the legacy 1/2/4 mask layout; bit 0 is the
    // left button. (The modern `NSEventMask…` constants are event masks, not
    // button masks, so they do not apply here.)
    private let leftMouseButtonMask = 1 << 0

    /// Whether the left button was down at the previous poll. The edge is the
    /// signal: it distinguishes "a drag is in flight over the notch" from "the
    /// user is holding the button down in some other app", and it is what tells
    /// us a drag just *ended* so click-through can be restored.
    private var dragButtonWasDown = false
    /// True while we are actively holding the panel open for a drag. Separate
    /// from `dragButtonWasDown` because the panel should stay open through the
    /// gap between release and the next poll.
    private var dragHoldingOpen = false
    /// True once the panel has been made interactive because a drag started.
    /// Tracked separately from `dragHoldingOpen`: the window must be a drop
    /// candidate for the whole drag, even while the pointer is nowhere near
    /// the notch and the panel is still closed.
    private var dragArmed = false
    /// Mirrors `dragArmed` onto the hosting view, which is the object that has
    /// to claim the drag in `hitTest`. Set by `makeWindow`.
    private var mirrorDragArmed: ((Bool) -> Void)?
    /// Last hover result, so the transition log fires once per change instead of
    /// on every mouse-moved.
    private var lastHoverInside = false

    /// Set when the current drag actually delivered files to the app. Without
    /// it a cancelled drag is indistinguishable from a successful one, and a
    /// cancelled drag must not leave the panel pinned open.
    private var dragDeliveredFiles = false

    /// Called from the drop path once files are genuinely in hand.
    func noteDragDeliveredFiles() {
        dragDeliveredFiles = true
    }

    /// Drives the whole drag interaction from the button mask.
    ///
    /// The previous version only flipped `ignoresMouseEvents` and then waited
    /// for AppKit to deliver `draggingEntered`. That is the flaky part: a window
    /// with `ignoresMouseEvents = true` is skipped by the drag destination
    /// routing, so AppKit may never send `draggingEntered` at all — the panel
    /// then never expanded, and if it never expanded the drop had nowhere to
    /// land and the file was released onto the desktop as a Finder tile. That
    /// is the "drag only works when the panel happens to be open" behaviour.
    ///
    /// Opening the panel from the poll itself removes the dependency on the
    /// callback arriving: AppKit's `draggingEntered` / `performDragOperation`
    /// stay wired up and now work because the window is interactive by the time
    /// the drag reaches it.
    private func pollForDrag() {
        guard let metrics else { return }
        let leftDown = NSEvent.pressedMouseButtons & leftMouseButtonMask != 0
        let collapsedZone = NotchGeometry.dropZone(on: metrics.screen, collapsed: metrics.collapsed)
        let activeZone = (dragHoldingOpen || presentedExpanded)
            ? collapsedZone.union(interactiveRect.insetBy(dx: -40, dy: -40))
            : collapsedZone
        let decision = dragDecision(
            leftDown: leftDown,
            wasDown: dragButtonWasDown,
            holdingOpen: dragHoldingOpen,
            location: NSEvent.mouseLocation,
            zone: activeZone
        )
        dragButtonWasDown = leftDown

        switch decision {
        case .none:
            break

        case .dragBegan:
            dragArmed = true
            mirrorDragArmed?(true)
            if panel?.ignoresMouseEvents == true {
                panel?.ignoresMouseEvents = false
            }
            NKLog("[Drag] began — window armed as drop destination")

        case .dragEnded:
            endDragHold()

        case .leaveZone:
            endDragHold()

        case .enterZone, .holdOpen:
            dragArmed = true
            mirrorDragArmed?(true)
            if panel?.ignoresMouseEvents == true {
                panel?.ignoresMouseEvents = false
            }
            // Cancel any pending collapse so the panel cannot fold up mid-drag.
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            openWorkItem?.cancel()
            openWorkItem = nil
            if decision == .enterZone {
                dragHoldingOpen = true
                NKLog("[Drag] entered notch zone — expanding panel")
                onDragHover?(true)
            }
        }
    }

    /// Releases the panel after a drag finishes and restores click-through.
    private func endDragHold() {
        let wasOpen = dragHoldingOpen
        dragHoldingOpen = false

        // Delay disarming by 600ms so AppKit's dragging manager can invoke
        // performDragOperation before the window ignores mouse events.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            let delivered = self.dragDeliveredFiles
            self.dragArmed = false
            self.mirrorDragArmed?(false)
            self.dragDeliveredFiles = false
            NKLog("[Drag] endDragHold finalized — wasOpen=\(wasOpen) delivered=\(delivered)")
            if wasOpen && !delivered {
                self.onDragHover?(false)
                self.onDragCancelled?()
            }
            if !delivered && !NSMouseInRect(NSEvent.mouseLocation, self.interactiveRect, false) {
                self.panel?.ignoresMouseEvents = true
            }
        }
    }

    // MARK: - Hover

    private func evaluateHover(at location: NSPoint) {
        let inside = NSMouseInRect(location, interactiveRect, false)
        trace("hover at (\(Int(location.x)),\(Int(location.y))) inside=\(inside)")
        // Logged only on transitions. Logging every mouse-moved would drown the
        // file in noise and make it useless for reading a drag sequence.
        if inside != lastHoverInside {
            lastHoverInside = inside
            NKLog("[Hover] inside=\(inside) dragArmed=\(dragArmed) holding=\(dragHoldingOpen)")
        }
        if inside {
            if panel?.ignoresMouseEvents == true {
                panel?.ignoresMouseEvents = false
            }
            disarmAutoCollapse()
            if openWorkItem == nil {
                if openDelay <= 0 {
                    onHoverChange?(true)
                } else {
                    let work = DispatchWorkItem { [weak self] in
                        self?.openWorkItem = nil
                        self?.onHoverChange?(true)
                    }
                    openWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + openDelay, execute: work)
                }
            }
        } else {
            openWorkItem?.cancel()
            openWorkItem = nil
            if !presentedExpanded {
                // Pointer left while only in preview (idleHover). Cancel immediately
                // so the dwell timer never promotes to expanded after the user has left.
                collapseWorkItem?.cancel()
                collapseWorkItem = nil
                if !dragArmed && !dragHoldingOpen && !dragDeliveredFiles {
                    panel?.ignoresMouseEvents = true
                }
                onHoverChange?(false)
            } else if collapseWorkItem == nil {
                // When already expanded, apply the grace period so reaching for
                // controls doesn't snap the panel shut mid-reach.
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.collapseWorkItem = nil
                    if !self.dragArmed && !self.dragHoldingOpen && !self.dragDeliveredFiles {
                        self.panel?.ignoresMouseEvents = true
                    }
                    NKLog("[Hover] collapse fired — releasing panel")
                    self.onHoverChange?(false)
                }
                collapseWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
            }
        }
    }

    /// Called by the view layer whenever the presented size changes, so the
    /// click-through region tracks the animating shape exactly. Using the real
    /// presented size (rather than a derived constant) is what keeps the outer
    /// header buttons clickable at every panel width.
    func setPresented(size: CGSize, expanded: Bool) {
        guard let metrics else { return }
        presentedSize = size
        presentedExpanded = expanded
        interactiveRect = NotchGeometry.presentedFrame(on: metrics.screen, size: size)
        let inside = NSMouseInRect(NSEvent.mouseLocation, interactiveRect, false)
        if !dragArmed && !dragHoldingOpen && !dragDeliveredFiles {
            panel?.ignoresMouseEvents = !inside
        } else {
            panel?.ignoresMouseEvents = false
        }
        trace("presented \(Int(size.width))x\(Int(size.height)) expanded=\(expanded) mouseInside=\(inside)")
        if expanded && inside {
            if panel?.isKeyWindow == false {
                panel?.makeKey()
            }
        }
    }

    /// Legacy entry point kept for the hover/pin pipeline. The actual hit
    /// region now comes from `setPresented(size:expanded:)`, which the view
    /// calls on every size change; this only guarantees the panel is key when
    /// it is pinned open.
    /// - Parameter pinned: a pinned panel was opened deliberately (menu bar), so
    ///   the idle timer must not close it.
    func setInteractive(expanded: Bool, pinned: Bool = false) {
        if expanded && !pinned {
            armAutoCollapse()
        } else {
            disarmAutoCollapse()
        }
        guard let metrics else { return }
        if presentedSize == .zero {
            let size = expanded ? NotchGeometry.fallbackExpandedSize : metrics.collapsed
            setPresented(size: size, expanded: expanded)
            return
        }
        if expanded {
            setPresented(size: presentedSize, expanded: expanded)
        }
    }

    /// Called by the view layer when the user tunes the width/height sliders.
    func updateCollapsedSize(_ newSize: CGSize) {
        guard var m = metrics else { return }
        m.collapsed = newSize
        metrics = m
        guard !presentedExpanded else {
            // Expanded: the presented size comes from the view, but the
            // collapsed fallback and the drop zone must still follow.
            return
        }
        setPresented(size: newSize, expanded: false)
    }

    /// Called while a drag session passes over the notch. Drag operations
    /// consume mouse-moved events, so the hover monitors never fire and the
    /// panel would stay click-through — the release would then land on the
    /// desktop and spawn a Finder tile instead of opening the panel.
    func handleDragHover(_ location: NSPoint) {
        guard let metrics else { return }
        // The poll owns the open/close lifecycle while a drag is in flight. If
        // it is already holding the panel open for this drag, do not let a
        // drag callback schedule a collapse underneath it — the two would
        // fight and the panel would flicker shut mid-drag.
        if dragHoldingOpen {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            return
        }
        let zone = NotchGeometry.dropZone(on: metrics.screen, collapsed: metrics.collapsed)
        let inside = NSMouseInRect(location, zone, false)
        if inside {
            if panel?.ignoresMouseEvents == true {
                panel?.ignoresMouseEvents = false
            }
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
            if openWorkItem == nil {
                openWorkItem = nil
                onDragHover?(true)
            }
        } else if collapseWorkItem == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.collapseWorkItem = nil
                self?.onDragHover?(false)
            }
            collapseWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
        }
    }

    // MARK: - Auto-collapse

    /// Schedules the panel to close once `collapseDelay` has passed with the
    /// pointer nowhere near it.
    ///
    /// This exists because nothing else covered the case where the panel opens
    /// without the pointer ever entering it. Both previous collapse sites were
    /// driven by "pointer moved outside", so a panel opened by a drop — or one
    /// left open when the pointer left without a final mouse-moved — had no timer
    /// waiting for it and simply stayed open. `hoverCloseDelay` from Settings is
    /// the delay used here, which is what that setting has always meant in
    /// practice.
    private func armAutoCollapse() {
        collapseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.collapseWorkItem = nil
            self?.performAutoCollapse()
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
    }

    /// Cancels a pending auto-collapse. Called whenever the pointer arrives, so
    /// the timer never fires while the user is actually looking at the panel.
    private func disarmAutoCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    /// Re-checks the world at fire time rather than trusting whatever was true
    /// when the timer was armed — a mouse-moved arriving in the gap is enough
    /// to make the earlier decision wrong.
    private func performAutoCollapse() {
        guard let panel else { return }

        guard !NSMouseInRect(NSEvent.mouseLocation, interactiveRect, false) else {
            // Pointer came back while the timer was pending. Hover owns the
            // panel from here.
            return
        }
        guard !dragArmed, !dragHoldingOpen else {
            // A live drag outranks the timer.
            armAutoCollapse()
            return
        }

        NKLog("[Hover] auto-collapse fired — pointer absent")
        panel.ignoresMouseEvents = true
        onHoverChange?(false)
    }

    // MARK: - Display changes

    /// Re-anchors to the notch. Called on display connect/disconnect and on
    /// resolution change — a user who unplugs their laptop display should get
    /// a floating capsule on the external one, not a window stuck offscreen.
    func reanchor(geometry newGeometry: NotchGeometry.Metrics) {
        guard let panel else { return }
        metrics = newGeometry
        let target = NotchGeometry.canvasFrame(on: newGeometry.screen)
        if target != panel.frame {
            panel.setFrame(target, display: true, animate: false)
        }
        setPresented(
            size: presentedExpanded ? presentedSize : newGeometry.collapsed,
            expanded: presentedExpanded
        )
        // Window numbers change when the display set changes; re-delegate.
        usingSkyLight = SkyLightBridge.shared.attach(panel)
        panel.orderFrontRegardless()
    }

    var isUsingSkyLight: Bool { usingSkyLight }

    /// Screen rect the window currently treats as interactive. Exposed for the
    /// `--hitdump` diagnostic, which is the only way to prove a header button
    /// is inside the hit region instead of assuming it.
    var interactiveRectDescription: String {
        let r = interactiveRect
        return "x=\(Int(r.origin.x)) y=\(Int(r.origin.y)) w=\(Int(r.width)) h=\(Int(r.height))"
    }

    /// Forces the panel to accept input for the duration of a diagnostic, so
    /// `hitTest` runs the same path a real click takes.
    func forceInteractiveForDiagnostics() {
        panel?.ignoresMouseEvents = false
    }
}

extension NotchWindowController: NSWindowDelegate {
    nonisolated func windowDidResignKey(_ notification: Notification) {
        // Losing focus (user clicked the desktop) should collapse the panel.
        MainActor.assumeIsolated { [weak self] in
            self?.onHoverChange?(false)
        }
    }
}


extension NotchWindowController: NSDraggingDestination {
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = Self.extractURLs(from: sender)
        guard !urls.isEmpty else { return [] }
        handleDragHover(sender.draggingLocation)
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = Self.extractURLs(from: sender)
        guard !urls.isEmpty else { return [] }
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        // Drag left window
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.extractURLs(from: sender)
        return !urls.isEmpty
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.extractURLs(from: sender)
        guard !urls.isEmpty else {
            NSLog("[Drag] WindowController performDragOperation — no file URLs")
            return false
        }
        NSLog("[Drag] WindowController performDragOperation — accepted \(urls.count) file(s)")
        noteDragDeliveredFiles()
        NotificationCenter.default.post(name: .notchFilesDelivered, object: nil)
        NotificationCenter.default.post(
            name: .notchDroppedFiles,
            object: nil,
            userInfo: ["urls": urls]
        )
        return true
    }

    static func extractURLs(from sender: NSDraggingInfo) -> [URL] {
        var result: [URL] = []
        let pboard = sender.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let objects = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            result.append(contentsOf: objects)
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
        return result.filter { $0.isFileURL && !$0.hasDirectoryPath }
    }
}
