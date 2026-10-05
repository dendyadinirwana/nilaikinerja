import SwiftUI
import AppKit

/// A swipe-to-reveal row, ported from React Bits' `SwipeRow`.
///
/// The geometry is transcribed rather than approximated, because the layout is
/// load-bearing and easy to get subtly backwards:
///
/// ```text
///   |<--------------------- row width W --------------------->|
///   . . . . . . . . . . [secondary] [primary red block] . . . .   exposed = e
///                     ^W-2A      ^W-A
/// ```
///
/// Two facts drive the whole component, and both are easy to get wrong:
///
/// 1. The primary block is a **full-width** rect anchored at `W - A`, not an
///    `A`-wide button that grows. It is translated left by `max(0, e - A)` once
///    the drag passes the commit point, so it sweeps across the entire row.
/// 2. Because the block sweeps and the label does not, the label needs a
///    counter-translate. Without it the label is left behind at the trailing
///    edge, uncovered, while the red passes underneath.
///
/// What did not survive the port, and why:
/// - `motion/react` and `@hugeicons` are React-only. Spring physics map onto
///   SwiftUI's `spring`, which takes the same `bounce` parameter, and icons are
///   SF Symbols — the native idiom regardless.
/// - `navigator.vibrate` has no macOS equivalent.
/// - Pointer Events and the window-level move/up listeners collapse into one
///   SwiftUI `DragGesture`; a macOS drag delivers `.onEnded` even when the
///   cursor leaves the window, so the global listener adds nothing.
struct SwipeRow<Content: View>: View {
    /// One drawer action. The primary sits at the trailing edge and is the
    /// full-swipe target; secondaries stack inboard of it.
    struct Action: Identifiable {
        let id: String
        let label: String
        let symbol: String
        var isPrimary: Bool = false
        /// Overrides the drawer base for a secondary. `nil` means drawer color.
        var tint: Color?
    }

    @ViewBuilder var content: () -> Content

    var actions: [Action]
    /// Fired the moment a button is pressed, before the row settles.
    var onAction: (Action) -> Void
    /// Fired once the row has finished folding. This is where the row is
    /// actually removed from the model.
    var onCommit: (Action) -> Void
    /// Folds the row when a secondary is pressed. A primary always folds.
    var dismissSecondary: Bool = false

    // Palette, from the reference CSS custom properties.
    var rowColor = Color(hex: 0x27272A)
    var drawerColor = Color(hex: 0x3F3F46)
    var actionColor = Color(hex: 0xE5484D)
    var textColor = Color(hex: 0xF5F5F5)

    var height: CGFloat = 64
    var radius: CGFloat = 16
    var actionWidth: CGFloat = 80
    var snapBounce: CGFloat = 0.2
    var resistance: CGFloat = 0.55
    var collapseMs: Double = 0.2
    var commitAt: CGFloat = 0.6
    var fullSwipe: Bool = true
    var disabled: Bool = false
    var marginBottom: CGFloat = 8
    /// Fired on a plain tap — a press that never became a drag. This is the
    /// "open the detail" affordance; the swipe actions are for destructive and
    /// secondary verbs, which is why tapping the row body is a separate gesture
    /// rather than "no swipe happened".
    var onTap: (() -> Void)?
    /// Screenshot-verification pose: `nil`, `"open"`, or `"leap"`. Not for
    /// normal use — a real gesture drives the row.
    var pose: String? = nil

    @StateObject private var state = SwipeRowState()

    private var primary: Action? { actions.first }
    private var secondary: [Action] { Array(actions.dropFirst()) }
    private var drawerWidth: CGFloat { CGFloat(actions.count) * actionWidth }

    /// `content` is declared last so call sites can use trailing-closure
    /// syntax. With the memberwise initialiser Swift picks the last *labelled*
    /// parameter for trailing-closure binding, and a `@ViewBuilder var` in the
    /// middle of the list cannot be inferred.
    init(
        actions: [Action],
        onAction: @escaping (Action) -> Void,
        onCommit: @escaping (Action) -> Void,
        dismissSecondary: Bool = false,
        rowColor: Color = Color(hex: 0x27272A),
        drawerColor: Color = Color(hex: 0x3F3F46),
        actionColor: Color = Color(hex: 0xE5484D),
        textColor: Color = Color(hex: 0xF5F5F5),
        height: CGFloat = 64,
        radius: CGFloat = 16,
        actionWidth: CGFloat = 80,
        snapBounce: CGFloat = 0.2,
        resistance: CGFloat = 0.55,
        collapseMs: Double = 0.2,
        commitAt: CGFloat = 0.6,
        fullSwipe: Bool = true,
        disabled: Bool = false,
        marginBottom: CGFloat = 8,
        onTap: (() -> Void)? = nil,
        pose: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.actions = actions
        self.onAction = onAction
        self.onCommit = onCommit
        self.onTap = onTap
        self.dismissSecondary = dismissSecondary
        self.rowColor = rowColor
        self.drawerColor = drawerColor
        self.actionColor = actionColor
        self.textColor = textColor
        self.height = height
        self.radius = radius
        self.actionWidth = actionWidth
        self.snapBounce = snapBounce
        self.resistance = resistance
        self.collapseMs = collapseMs
        self.commitAt = commitAt
        self.fullSwipe = fullSwipe
        self.disabled = disabled
        self.marginBottom = marginBottom
        self.pose = pose
        self.content = content
    }

    var body: some View {
        // The measured width has to come from a reader that actually gets laid
        // out. A `GeometryReader` in a zero-height frame measures fine but
        // collapses its overlay to zero height too, which silently hides every
        // layer inside it — the state is correct and nothing renders.
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                rail(width: geo.size.width)
                commitBlock(width: geo.size.width)
                surface(width: geo.size.width)
            }
            .frame(width: geo.size.width, height: height, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onAppear { apply(w: geo.size.width) }
            .onChange(of: geo.size.width) { _, new in apply(w: new) }
        }
        .frame(height: state.isCollapsed ? 0 : height)
        .clipped()
        .padding(.bottom, state.isCollapsed ? 0 : marginBottom)
        .opacity(disabled ? 0.55 : (state.isCollapsed ? 0 : 1))
        .animation(.easeOut(duration: collapseMs), value: state.isCollapsed)
        .allowsHitTesting(!state.isCollapsed)
    }

    /// Feeds the measured width to the state and re-applies the pose.
    ///
    /// Both have to live in one place: a screenshot pose needs a measured width
    /// to be meaningful — `"leap"` positions the commit block at `width` — and
    /// `onChange` alone does not fire when the width is stable from the first
    /// layout, which is the common case.
    private func apply(w: CGFloat) {
        state.configure(
            width: w,
            actionWidth: actionWidth,
            drawerWidth: drawerWidth,
            resistance: resistance,
            commitAt: commitAt,
            canCommit: fullSwipe && !actions.isEmpty,
            snapBounce: snapBounce
        )
        if let pose { state.pose(pose) }
    }

    // MARK: - Rail

    /// The drawer rail. Sized to the drawer, not the row, and slid in by
    /// `D - e`.
    ///
    /// The reference's rail is `inset: 0` with the actions absolutely placed
    /// against the trailing edge, so the pair `(rail width, rail offset)` has to
    /// reproduce `translateX(D - e)` — the offset is measured from the
    /// *drawer's* width. Sizing the rail to the row and offsetting by
    /// `W - e` slides it a full row width too far, which parks the actions off
    /// screen entirely.
    private func rail(width: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            drawerColor

            // Measured from the trailing edge: the first secondary is `A` in,
            // the next `2A`. Stacking from the leading edge would put the
            // primary on the wrong side.
            ForEach(Array(secondary.enumerated()), id: \.element.id) { index, action in
                actionButton(action, width: actionWidth, fill: action.tint ?? drawerColor)
                    .offset(x: -CGFloat(index + 1) * actionWidth)
            }

            // The primary is also reachable by tap, not only by a full swipe.
            // It takes the trailing slot, which is where the reference parks
            // the commit block — but that block only draws once the drag
            // commits, so without this the slot is dead space in the open
            // drawer.
            if let primary {
                actionButton(primary, width: actionWidth, fill: actionColor)
            }
        }
        .frame(width: width, height: height)
        .offset(x: SwipeLayout.railOffsetX(exposed: state.exposed, state.metrics))
    }

    // MARK: - Commit block

    /// The full-width red rect that sweeps the row on commit.
    ///
    /// Drawn only while the row is actually leaping. The reference parks this
    /// block at `[W - A, W]` at rest, which is the same slot the last secondary
    /// occupies — so a literal transcription leaves the red sitting on top of
    /// "Rekap" whenever the drawer is merely open. The block is the commit
    /// affordance, so it appears with the commit and not before.
    private func commitBlock(width: CGFloat) -> some View {
        let shift = state.isLeaping ? max(0, state.exposed - actionWidth) : 0
        return Group {
            if state.isLeaping, let primary {
                ZStack(alignment: .topLeading) {
                    actionColor
                    // Counter-translate. `shift - (W - A) / 2` pins the label to
                    // a constant x in the row while the block slides underneath,
                    // so the text stays put instead of being abandoned at the
                    // edge.
                    actionLabel(primary, size: 20, textColor: actionColor.contrastingText)
                        .frame(width: actionWidth, height: height)
                        .offset(x: shift - (width - actionWidth) / 2)
                }
                .frame(width: width, height: height)
                .offset(x: width - actionWidth - shift)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Surface

    private func surface(width: CGFloat) -> some View {
        content()
            // `minHeight` pins the card to the row height. A plain
            // `frame(height:)` only *proposes* that height, so a one-line row
            // collapses to its intrinsic size — which leaves the list with
            // ragged cards whose hit regions do not match what is drawn.
            .frame(maxWidth: .infinity)
            .frame(minHeight: height, maxHeight: height, alignment: .topLeading)
            .background(rowColor)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .overlay {
                TrackpadSwipeView(
                    state: state,
                    disabled: disabled,
                    onCommitPrimary: {
                        if let primary {
                            DispatchQueue.main.asyncAfter(deadline: .now() + collapseMs) {
                                onCommit(primary)
                            }
                        }
                    }
                )
            }
            .foregroundStyle(textColor)
            .contentShape(Rectangle())
            .offset(x: -state.exposed)
            .gesture(dragGesture)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityName)
            .accessibilityAction(named: "Hapus") { trigger(primary) }
            .accessibilityAction(named: "Rekap") { trigger(secondary.first) }
    }

    private var accessibilityName: String {
        let titles = actions.map(\.label).joined(separator: ", ")
        return "\(titles). Swipe kiri atau gunakan VoiceOver actions."
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !disabled, state.phase == .idle || state.phase == .dragging else { return }
                if state.phase != .dragging { state.beginDrag() }
                state.updateDrag(
                    translation: value.translation.width,
                    at: ProcessInfo.processInfo.systemUptime
                )
            }
            .onEnded { value in
                guard !disabled, state.phase == .dragging else { return }
                // A press that never cleared the hysteresis is a tap, not a
                // swipe — fire the detail affordance before settling, or the
                // drawer animation eats the gesture.
                let wasTap = !state.wasDrag
                state.endDrag(at: ProcessInfo.processInfo.systemUptime)
                if wasTap {
                    if state.exposed > 10 {
                        state.closeDrawer()
                    } else {
                        onTap?()
                    }
                } else if state.phase == .committing, let primary {
                    DispatchQueue.main.asyncAfter(deadline: .now() + collapseMs) {
                        onCommit(primary)
                    }
                }
            }
    }

    // MARK: - Actions

    private func actionButton(_ action: Action, width: CGFloat, fill: Color) -> some View {
        return Button {
            trigger(action)
        } label: {
            actionLabel(action, size: 20, textColor: fill.contrastingText)
                .frame(width: width, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(fill)
        // The 150ms white wash on hover from the reference CSS.
        .overlay(
            Rectangle()
                .fill(.white)
                .opacity(state.hoveringAction == action.id ? 0.08 : 0)
                .animation(.easeOut(duration: 0.15), value: state.hoveringAction)
        )
        .onHover { state.hoveringAction = $0 ? action.id : nil }
    }

    private func actionLabel(_ action: Action, size: CGFloat, textColor: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: action.symbol)
                .font(.system(size: max(size, 16), weight: .semibold))
            Text(action.label)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(textColor)
        // 0.97 press scale from the reference CSS.
        .scaleEffect(state.pressedAction == action.id ? 0.97 : 1)
        .animation(.easeOut(duration: 0.16), value: state.pressedAction)
        .onLongPressGesture(minimumDuration: 0, pressing: { down in
            state.pressedAction = down ? action.id : nil
        }, perform: {})
    }

    // MARK: - Commit

    private func trigger(_ action: Action?) {
        guard let action, state.phase == .idle else { return }
        onAction(action)

        // A primary always folds, because committing it means the row is going
        // away. A secondary only folds when asked to; otherwise the row stays
        // put and merely closes the drawer.
        guard action.isPrimary || dismissSecondary else {
            state.closeDrawer()
            return
        }
        state.commit(leaping: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseMs) {
            onCommit(action)
        }
    }
}

/// Gesture state for one row.
///
/// `@StateObject`, not `@ObservedObject`: SwiftUI reconstructs the view struct
/// on every render, and an `@ObservedObject` default expression would build a
/// fresh model each time, silently resetting the drag mid-gesture.
@MainActor
final class SwipeRowState: ObservableObject {
    enum Phase { case idle, dragging, committing, collapsing }

    /// How much of the drawer is uncovered. Can go slightly negative, which
    /// nudges the surface the other way — the reference rubber-bands the
    /// opposite direction rather than clamping, and the small overscroll is
    /// what makes the row feel attached to something.
    @Published private(set) var exposed: CGFloat = 0
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isLeaping = false
    @Published private(set) var isCollapsed = false
    @Published var hoveringAction: String?
    @Published var pressedAction: String?

    private(set) var width: CGFloat = 0
    private var actionWidth: CGFloat = 80
    private var drawerWidth: CGFloat = 0
    private var resistance: CGFloat = 0.55
    private var commitAt: CGFloat = 0.6
    private var canCommitNow: Bool = true
    private var snapBounce: CGFloat = 0.2
    private var anchor: CGFloat = 0
    private var didMove = false
    private var history: [(time: TimeInterval, exposed: CGFloat)] = []

    /// Below this the row does not budge, so an ordinary tap never leaves the
    /// drawer stuck open.
    private static let hysteresis: CGFloat = 10
    /// Past this speed the row snaps to the nearer end regardless of position.
    private static let flickVelocity: CGFloat = 110
    /// Velocity is clamped before it reaches a spring; past this the animation
    /// is indistinguishable from an instant jump.
    private static let maxVelocity: CGFloat = 1500
    /// Exponential-decay constant for the slow-release projection. Mirrors
    /// `DECEL` in the reference.
    private static let decel: CGFloat = 0.998

    func configure(
        width: CGFloat,
        actionWidth: CGFloat,
        drawerWidth: CGFloat,
        resistance: CGFloat,
        commitAt: CGFloat,
        canCommit: Bool,
        snapBounce: CGFloat
    ) {
        self.width = width
        self.actionWidth = actionWidth
        self.drawerWidth = drawerWidth
        self.resistance = min(max(resistance, 0.05), 1)
        self.commitAt = commitAt
        self.canCommitNow = canCommit
        self.snapBounce = snapBounce
    }

    /// The metrics the pure layout model runs on. One source of truth: the view
    /// and the tests must not be able to disagree about the geometry.
    var metrics: SwipeLayout.Metrics {
        SwipeLayout.Metrics(
            width: width,
            actionWidth: actionWidth,
            actionCount: max(1, Int((drawerWidth / actionWidth).rounded())),
            resistance: resistance,
            commitAt: commitAt,
            fullSwipe: canCommitNow,
            snapBounce: snapBounce
        )
    }

    private var commitThreshold: CGFloat { SwipeLayout.commitThreshold(metrics) }
    private var canCommit: Bool { SwipeLayout.canCommit(metrics) }
    private func map(_ raw: CGFloat) -> CGFloat { SwipeLayout.map(raw, metrics) }

    // MARK: Drag lifecycle

    func beginDrag() {
        anchor = exposed
        phase = .dragging
        didMove = false
        history = [(ProcessInfo.processInfo.systemUptime, exposed)]
    }

    func updateDrag(translation: CGFloat, at time: TimeInterval) {
        let delta = -translation
        // Past the hysteresis gate on the first move, the row is committed to
        // this gesture and tracks the finger exactly — including when the drag
        // starts from an already-open drawer.
        if history.count == 1, abs(delta) < Self.hysteresis, anchor == 0 { return }
        didMove = true
        exposed = map(anchor + delta)
        isLeaping = canCommit && exposed >= commitThreshold
        history.append((time, exposed))
        if history.count > 5 { history.removeFirst() }
    }

    /// True when the press travelled far enough to count as a swipe. A press
    /// that stayed inside the hysteresis is a tap, and only a tap should open
    /// the row's detail.
    var wasDrag: Bool { didMove }

    func endDrag(at time: TimeInterval) {
        phase = .idle
        let velocity = velocity(at: time)
        isLeaping = false

        // Past the threshold the row is already committed; a flick past it
        // commits no matter where the finger stopped.
        if canCommit, exposed >= commitThreshold {
            commit(leaping: true, velocity: velocity)
            return
        }

        // A fast flick snaps to the nearer end. A slow release projects where
        // the row was still heading and compares that to the midpoint, so a
        // decelerating drag past halfway still opens.
        let target: CGFloat = abs(velocity) >= Self.flickVelocity
            ? (velocity > 0 ? drawerWidth : 0)
            : (exposed + Self.project(velocity) > drawerWidth / 2 ? drawerWidth : 0)

        withAnimation(
            .spring(response: 0.4, dampingFraction: bounceFraction)
        ) {
            exposed = target
        }
    }

    /// Where a release at this velocity would coast to. Mirrors `project` in
    /// the reference: velocity is per-second, scaled by the decay ratio.
    private static func project(_ velocity: CGFloat) -> CGFloat {
        ((velocity / 1000) * decel) / (1 - decel)
    }

    /// Velocity from the first and last sample of the recent history, so a
    /// single stuttered frame cannot fake a flick.
    private func velocity(at time: TimeInterval) -> CGFloat {
        history.append((time, exposed))
        guard history.count >= 2 else { return 0 }
        let first = history[0], last = history[history.count - 1]
        let dt = max(last.time - first.time, 0.001)
        let v = ((last.exposed - first.exposed) / dt) * 1000
        return min(max(v, -Self.maxVelocity), Self.maxVelocity)
    }

    private var bounceFraction: CGFloat {
        1 - snapBounce * 0.6
    }

    // MARK: Commit

    /// Runs the leap, then the fold, so the row visibly closes before the model
    /// drops it. Collapsing first would make the deletion feel abrupt.
    ///
    /// Takes a plain `Bool` rather than the nested `Action` type: `Action`
    /// lives inside the generic `SwipeRow<Content>`, so this non-generic state
    /// object cannot name it.
    func commit(leaping: Bool, velocity: CGFloat = 0) {
        phase = .committing
        isLeaping = leaping
        if leaping {
            withAnimation(
                .spring(response: 0.3, dampingFraction: bounceFraction)
                    .speed(abs(velocity) > Self.flickVelocity ? 1.2 : 1)
            ) {
                exposed = width
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            self.isCollapsed = true
            self.phase = .collapsing
        }
    }

    /// Closes the drawer without folding — for secondary actions.
    func closeDrawer() {
        isLeaping = false
        withAnimation(.spring(response: 0.3, dampingFraction: bounceFraction)) {
            exposed = 0
        }
    }

    /// Restores the row after a cancelled commit.
    func reset() {
        phase = .idle
        isLeaping = false
        isCollapsed = false
        withAnimation(.spring(response: 0.3, dampingFraction: bounceFraction)) {
            exposed = 0
        }
    }

    /// Forces a static pose for screenshot verification. The swipe gesture
    /// cannot be driven without a real pointer, so the drawer states are
    /// otherwise only checkable by hand — which is how an inverted action
    /// order shipped once.
    func pose(_ pose: String) {
        isCollapsed = false
        isLeaping = false
        phase = .idle
        switch pose {
        case "open":
            exposed = drawerWidth
        case "leap":
            exposed = width
            isLeaping = true
        default:
            exposed = 0
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Picks black or white for text on this background, using the same
    /// relative-luminance threshold as the reference's `onColor`.
    var contrastingText: Color {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return .white }
        let l = 0.299 * c.redComponent * 255
            + 0.587 * c.greenComponent * 255
            + 0.114 * c.blueComponent * 255
        return l >= 150 ? Color(hex: 0x111111) : .white
    }
}

// MARK: - Trackpad swipe support

struct TrackpadSwipeView: NSViewRepresentable {
    @ObservedObject var state: SwipeRowState
    var disabled: Bool
    var onCommitPrimary: () -> Void

    func makeNSView(context: Context) -> TrackpadNSView {
        let view = TrackpadNSView()
        view.state = state
        view.disabled = disabled
        view.onCommitPrimary = onCommitPrimary
        return view
    }

    func updateNSView(_ nsView: TrackpadNSView, context: Context) {
        nsView.state = state
        nsView.disabled = disabled
        nsView.onCommitPrimary = onCommitPrimary
    }
}

final class TrackpadNSView: NSView {
    var state: SwipeRowState?
    var disabled: Bool = false
    var onCommitPrimary: (() -> Void)?

    private var isTrackingHorizontal = false
    private var accumulatedDelta: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Intercept scroll wheel events so two-finger trackpad gestures drive the row.
        // Taps, mouse down, mouse up, and click-drags pass straight through to SwiftUI.
        if let current = NSApp.currentEvent, current.type == .scrollWheel {
            return self
        }
        return nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard let state, !disabled else {
            super.scrollWheel(with: event)
            return
        }

        let isHorizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 0.7
        if event.hasPreciseScrollingDeltas && (isHorizontal || isTrackingHorizontal) {
            if event.phase == .began {
                isTrackingHorizontal = true
                accumulatedDelta = 0
                state.beginDrag()
            }

            if isTrackingHorizontal {
                accumulatedDelta += event.scrollingDeltaX
                state.updateDrag(
                    translation: accumulatedDelta,
                    at: ProcessInfo.processInfo.systemUptime
                )
            }

            if event.phase == .ended || event.phase == .cancelled {
                if isTrackingHorizontal {
                    isTrackingHorizontal = false
                    state.endDrag(at: ProcessInfo.processInfo.systemUptime)
                    if state.phase == .committing {
                        onCommitPrimary?()
                    }
                }
            }
        } else {
            super.scrollWheel(with: event)
        }
    }
}
