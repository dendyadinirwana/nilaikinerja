import AppKit
import SwiftUI
import Combine

/// Hover and pin state, shared between the window controller and the view.
@MainActor
final class HoverState: ObservableObject {
    @Published private(set) var isOver: Bool = false
    /// Set when the user opens the panel from the menu bar. A pinned panel
    /// stays open until explicitly dismissed.
    ///
    /// Every write is logged with its caller. `pinned` is the one flag that can
    /// hold the panel open forever — `setOver` refuses to touch `isOver` while
    /// it is set — so a single stray `true` turns every later collapse into a
    /// no-op. The log showed 27 "BLOCKED by pinned" messages with no drop ever
    /// accepted, which proved the write came from somewhere nobody had looked.
    @Published fileprivate var pinnedStorage = false

    var pinned: Bool {
        get { pinnedStorage }
        set {
            guard pinnedStorage != newValue else { return }
            let caller = Thread.callStackSymbols
                .prefix(6)
                .map { $0.components(separatedBy: " ").last ?? $0 }
                .joined(separator: " <- ")
            NSLog("[Panel] pinned \(newValue ? "SET" : "CLEARED") by: \(caller)")
            pinnedStorage = newValue
        }
    }

    /// True when the current pin came from a file drop rather than from the
    /// menu bar.
    ///
    /// `pinned` is sticky by design — a panel the user opened deliberately from
    /// the menu bar should not close on its own. But a drop pin is different: a
    /// cancelled drag that happened to end over the panel still routed through
    /// `MochiDropHandler`, which pinned it, and with no release path the panel
    /// stayed open forever and the `hoverCloseDelay` setting stopped applying
    /// entirely. Tracking the source is what lets a cancelled drag undo its own
    /// pin without also closing a panel the user opened on purpose.
    @Published private(set) var pinFromDrop = false

    /// Releases a pin that a drop put there. No-op for a menu-bar pin.
    func releaseDropPin() {
        guard pinned, pinFromDrop else { return }
        pinned = false
        pinFromDrop = false
        logInputs("releaseDropPin()")
    }

    func setPinned(_ value: Bool, fromDrop: Bool) {
        pinFromDrop = value && fromDrop
        pinned = value
    }
    /// True while a file drag is over the notch. A drag session consumes
    /// mouse-moved events, so this is the only signal that can open the panel
    /// while a file is being dragged in — without it the release lands on the
    /// desktop and spawns a Finder tile instead.
    @Published var dragActive: Bool = false

    /// True when the panel should be presented, from any source.
    var isExpanded: Bool { isOver || pinned || dragActive }

    /// Logged on every change. This is the only place that can say *which* of
    /// the three inputs is holding the panel open — `onHoverChange(false)`
    /// firing 157 times while the panel stays open is indistinguishable from a
    /// correct collapse without it.
    private func logInputs(_ reason: String) {
        NSLog("[Panel] expanded=\(isExpanded) — over=\(isOver) pinned=\(pinned) drag=\(dragActive) (\(reason))")
    }

    func setOver(_ over: Bool) {
        // A pin outranks a pointer that merely left the panel.
        guard !pinned else {
            if over != isOver { logInputs("setOver(\(over)) BLOCKED by pinned") }
            return
        }
        if over != isOver {
            isOver = over
            logInputs("setOver(\(over))")
        }
    }

    /// Called by the window controller when a drag starts or ends.
    func setDrag(_ dragging: Bool) {
        if dragging != dragActive {
            dragActive = dragging
            logInputs("setDrag(\(dragging))")
        }
    }
}

/// Root view: the morphing notch surface plus the hover wiring.
///
/// Hover is owned by `NotchWindowController` (it needs global mouse monitors,
/// which SwiftUI cannot install) and forwarded here as a state change.
struct RootView: View {
    @ObservedObject var coordinator: TrackingCoordinator
    @ObservedObject var windowModel: WindowBridge
    @ObservedObject var hover: HoverState
    @ObservedObject var motion: NotchMotion

    init(
        coordinator: TrackingCoordinator,
        windowModel: WindowBridge,
        hover: HoverState,
        motion: NotchMotion
    ) {
        self.coordinator = coordinator
        self.windowModel = windowModel
        self.hover = hover
        self.motion = motion
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let geometry = windowModel.geometry {
                NotchSurface(
                    coordinator: coordinator,
                    form: windowModel.checkpointForm,
                    mode: windowModel.panelMode,
                    today: windowModel.today,
                    settings: windowModel.settings,
                    liveIcon: windowModel.liveIcon,
                    reveal: windowModel.reveal,
                    motion: motion,
                    isNotched: geometry.isNotched,
                    isExpanded: hover.isExpanded,
                    collapsedSize: CGSize(
                        width: CGFloat(windowModel.settings.capsuleWidth),
                        height: CGFloat(windowModel.settings.capsuleHeight)
                    ),
                    onDrop: { urls in coordinator.attach(urls) },
                    onPresentedSize: { size, expanded in
                        windowModel.setPresentedSize(size, expanded: expanded)
                    }
                )
                .onAppear { motion.setHovering(hover.isOver) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: hover.isOver) { _, over in
            motion.setHovering(over)
        }
        .onChange(of: hover.dragActive) { _, dragging in
            motion.setHovering(hover.isOver || dragging)
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchTogglePanel)) { _ in
            // Menu-bar toggle: pin the panel open regardless of the pointer.
            // This is an explicit user action, so it is a *deliberate* pin and
            // is not released by a later cancelled drag.
            self.hover.setPinned(!self.hover.pinned, fromDrop: false)
            if !self.hover.pinned {
                self.coordinator.panelState = .collapsed
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchCollapsePanel)) { _ in
            self.hover.setPinned(false, fromDrop: false)
            self.coordinator.panelState = .collapsed
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchExpandPanel)) { _ in
            // A drop pin. The panel stays open so the prefilled form can be
            // reviewed, and it is released automatically once the drag that
            // caused it turns out to have been cancelled.
            self.hover.setPinned(true, fromDrop: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchDisplayChanged)) { _ in
            self.windowModel.refreshGeometry()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchDroppedFiles)) { note in
            guard let urls = note.userInfo?["urls"] as? [URL], !urls.isEmpty else { return }
            MochiDropHandler.handleDrop(
                urls: urls,
                coordinator: self.coordinator,
                mode: self.windowModel.panelMode
            )
        }
    }
}

/// Carries notch geometry to SwiftUI and keeps the AppKit window in sync.
@MainActor
final class WindowBridge: ObservableObject {
    @Published var geometry: NotchGeometry.Metrics?

    /// Exposed so `AppDelegate` can wire the controller's hover callback and
    /// the view can read the shared objects.
    let hoverState = HoverState()
    let checkpointForm = CheckpointForm()
    let notchMotion = NotchMotion()
    let panelMode = PanelMode()
    let today = TodaySummary()
    /// User-tunable geometry, hover timing, and the attachment folder. Lives
    /// here rather than in the view so the window controller and the panel read
    /// the same instance — a settings change has to resize the window, not just
    /// redraw inside it.
    let settings = AppSettings()
    /// Decoded character animations, loaded once at launch. Fifteen APNGs is
    /// a few hundred kilobytes of frames; re-reading them on hover would put
    /// disk I/O on the path the user is watching most closely.
    let liveIcon = LiveIconPack()
    /// The list entrance stagger. One per panel, so the rows can be sequenced
    /// against each other rather than each animating the instant the panel
    /// opens.
    let reveal = RevealCascade()

    private weak var controller: NotchWindowController?
    private var cancellables: Set<AnyCancellable> = []
    private var keyMonitor: Any?

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func bind(coordinator: TrackingCoordinator, controller: NotchWindowController) {
        self.controller = controller
        today.bind(store: coordinator.store)
        liveIcon.load()
        refreshGeometry()

        // Keyboard navigation for header tabs (Left/Right Arrow, Tab, Cmd+1..4)
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleKeyDown(event)
            }
        }

        controller.openDelay = settings.hoverOpenDelay
        controller.collapseDelay = settings.hoverCloseDelay

        settings.$hoverOpenDelay
            .receive(on: RunLoop.main)
            .sink { [weak controller] delay in controller?.openDelay = delay }
            .store(in: &cancellables)

        settings.$hoverCloseDelay
            .receive(on: RunLoop.main)
            .sink { [weak controller] delay in controller?.collapseDelay = delay }
            .store(in: &cancellables)

        settings.$capsuleWidth
            .combineLatest(settings.$capsuleHeight)
            .receive(on: RunLoop.main)
            .sink { [weak controller] width, height in
                controller?.updateCollapsedSize(CGSize(width: CGFloat(width), height: CGFloat(height)))
            }
            .store(in: &cancellables)

        // The window must know the shape's current size so it can route mouse
        // events to the right region and click through everywhere else.
        // `$pinned` was the projected publisher of a stored property. Now that
        // `pinned` is computed over `pinnedStorage`, the projection lives on the
        // stored property — and this is where the window's interactive region
        // follows the panel, so it has to keep observing the same changes.
        hoverState.$isOver
            .combineLatest(hoverState.$pinnedStorage)
            // No `removeDuplicates` here: the two inputs must stay separable,
            // because the window needs to know whether the panel is expanded
            // *and* whether that was deliberate. A pinned panel must survive the
            // idle timer; a hover-opened one must not. Filtering on the combined
            // flag would throw away exactly the distinction that matters.
            // `setInteractive` is idempotent, so repeated values are harmless.
            .sink { [weak self] over, pinned in
                self?.controller?.setInteractive(expanded: over || pinned, pinned: pinned)
            }
            .store(in: &cancellables)
    }

    /// Called by the view layer with the size actually on screen, so the
    /// click-through region matches the visible shape exactly. Deriving the
    /// region from a constant instead is what silently killed the outer header
    /// buttons: the panel width is a user setting, so the derived rect was
    /// narrower than the panel and the edge buttons fell through to the app
    /// underneath — while the keyboard shortcuts kept working, which made it
    /// look like the buttons themselves were broken.
    func setPresentedSize(_ size: CGSize, expanded: Bool) {
        controller?.setPresented(size: size, expanded: expanded)
    }

    func refreshGeometry() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let metrics = NotchGeometry.metrics(for: screen)
        let changed = metrics.collapsed != geometry?.collapsed
            || metrics.isNotched != geometry?.isNotched
        geometry = metrics
        if changed {
            controller?.reanchor(geometry: metrics)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // Only active when the panel is expanded
        guard hoverState.pinned || hoverState.isOver else {
            return event
        }

        // Do not intercept if user is actively editing a text field / text view
        if isEditingText() {
            return event
        }

        switch event.keyCode {
        case 123: // Left Arrow ←
            panelMode.previousTab()
            return nil

        case 124: // Right Arrow →
            panelMode.nextTab()
            return nil

        case 48: // Tab key
            if event.modifierFlags.contains(.shift) {
                panelMode.previousTab()
            } else {
                panelMode.nextTab()
            }
            return nil

        default:
            // Direct jump via Cmd + 1..4
            if event.modifierFlags.contains(.command) {
                switch event.keyCode {
                case 18: // '1'
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        panelMode.screen = .home
                    }
                    return nil
                case 19: // '2'
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        panelMode.screen = .list
                    }
                    return nil
                case 20: // '3'
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        panelMode.screen = .chat
                    }
                    return nil
                case 21: // '4'
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        panelMode.screen = .add
                    }
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }

    private func isEditingText() -> Bool {
        guard let keyWindow = NSApp.keyWindow,
              let responder = keyWindow.firstResponder else {
            return false
        }
        if let textView = responder as? NSTextView {
            return textView.isEditable
        }
        if let textField = responder as? NSTextField {
            return textField.isEditable
        }
        return false
    }
}
