import AppKit
import SwiftUI
import Combine

/// Visual presentation states for the 3-state MacBook M4 notch.
enum NotchVisualState: Equatable {
    /// State 1: Native notch cutout with glowing accent stroke. Mini Mochi and counter hidden.
    case idle
    /// State 2: Capsule preview with Mini Mochi and counter (~2s dwell timer).
    case idleHover
    /// State 3: Full expanded panel (home, activities, chat, forms).
    case expanded
}

/// Hover and pin state, shared between the window controller and the view.
@MainActor
final class HoverState: ObservableObject {
    @Published private(set) var visualState: NotchVisualState = .idle
    @Published private(set) var isOver: Bool = false
    @Published var dragActive: Bool = false
    @Published fileprivate var pinnedStorage = false

    private var dwellTask: Task<Void, Never>?

    /// Duration pointer must dwell in State 2 (idleHover) before expanding to State 3.
    var dwellDuration: TimeInterval = 1.0

    var isExpanded: Bool { visualState == .expanded }

    var pinned: Bool {
        get { pinnedStorage }
        set {
            guard pinnedStorage != newValue else { return }
            dwellTask?.cancel()
            dwellTask = nil
            pinnedStorage = newValue
            NKLog("[Panel] pinned \(newValue ? "SET" : "CLEARED")")
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                if newValue {
                    visualState = .expanded
                } else {
                    visualState = isOver ? .idleHover : .idle
                }
            }
        }
    }

    @Published private(set) var pinFromDrop = false

    func releaseDropPin() {
        guard pinned, pinFromDrop else { return }
        pinned = false
        pinFromDrop = false
        logInputs("releaseDropPin()")
        if !isOver {
            dwellTask?.cancel()
            dwellTask = nil
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                visualState = .idle
            }
        }
    }

    func setPinned(_ value: Bool, fromDrop: Bool) {
        pinFromDrop = value && fromDrop
        pinned = value
    }

    private func logInputs(_ reason: String) {
        NKLog("[Panel] state=\(visualState) over=\(isOver) pinned=\(pinned) drag=\(dragActive) (\(reason))")
    }

    func setOver(_ over: Bool) {
        guard !pinned else {
            if over != isOver { logInputs("setOver(\(over)) BLOCKED by pinned") }
            return
        }
        guard over != isOver else { return }
        isOver = over
        logInputs("setOver(\(over))")

        dwellTask?.cancel()
        dwellTask = nil

        if over {
            // If the panel is already expanded (user is clicking tabs or interacting),
            // stay expanded! Never demote back to idleHover while user is active.
            if visualState != .expanded {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    visualState = .idleHover
                }
                // Start dwell timer (default 1.0s) to transition to State 3
                let duration = dwellDuration
                dwellTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    guard let self, !Task.isCancelled, self.isOver, !self.pinned, self.visualState == .idleHover else { return }
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                        self.visualState = .expanded
                    }
                }
            }
        } else {
            // Pointer left: collapse back to State 1 (Idle)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                visualState = .idle
            }
        }
    }

    func expandNow() {
        dwellTask?.cancel()
        dwellTask = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            visualState = .expanded
        }
    }

    func setDrag(_ dragging: Bool) {
        guard dragging != dragActive else { return }
        dragActive = dragging
        dwellTask?.cancel()
        dwellTask = nil
        logInputs("setDrag(\(dragging))")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if dragging {
                // Dragging a file bypasses State 2 and opens State 3 immediately
                visualState = .expanded
            } else if !pinned {
                // When drag ends, only collapse if pointer is outside.
                // If pointer is inside an already expanded panel, stay expanded!
                if !isOver {
                    visualState = .idle
                }
            }
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
                    visualState: hover.visualState,
                    hardwareNotchSize: geometry.hardwareNotch,
                    collapsedSize: CGSize(
                        width: CGFloat(windowModel.settings.capsuleWidth),
                        height: CGFloat(windowModel.settings.capsuleHeight)
                    ),
                    onExpandNow: { hover.expandNow() },
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
        hoverState.$visualState
            .combineLatest(hoverState.$pinnedStorage)
            .sink { [weak self] visualState, pinned in
                self?.controller?.setInteractive(expanded: visualState == .expanded, pinned: pinned)
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
