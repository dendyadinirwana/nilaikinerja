import SwiftUI
import AppKit

/// Procedural vector mascot view matching the Coucou / Mochi front stage layout.
/// Features a superellipse body, eye-tracking towards the mouse cursor,
/// natural procedural breathing, random blinking, and interactive wave gestures.
@MainActor
final class MochiState: ObservableObject {
    @Published var isHappy: Bool = false
    @Published var isError: Bool = false
    @Published var isScanning: Bool = false
    @Published var tapCount: Int = 0
    @Published var isDragOver: Bool = false
    @Published var dropSuccessTitle: String? = nil
    @Published var dropErrorTitle: String? = nil
    @Published var scanningFilename: String? = nil
    @Published var pokeTrigger: Int = 0

    private var happyTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?

    func reactToTap() {
        tapCount += 1
        pokeTrigger += 1
        isHappy = true
        NSSound(named: "Glass")?.play()
        happyTask?.cancel()
        happyTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled {
                self.isHappy = false
            }
        }
    }

    func reactToScanning(filename: String) {
        errorTask?.cancel()
        happyTask?.cancel()
        scanTask?.cancel()
        isHappy = false
        isError = false
        dropErrorTitle = nil
        dropSuccessTitle = nil

        isScanning = true
        scanningFilename = filename
    }

    func reactToDrop(title: String) {
        scanTask?.cancel()
        isScanning = false
        scanningFilename = nil

        errorTask?.cancel()
        isError = false
        dropErrorTitle = nil

        dropSuccessTitle = title
        pokeTrigger += 1
        isHappy = true
        happyTask?.cancel()
        happyTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled {
                self.isHappy = false
                self.dropSuccessTitle = nil
            }
        }
    }

    func reactToError(reason: String) {
        scanTask?.cancel()
        isScanning = false
        scanningFilename = nil

        happyTask?.cancel()
        isHappy = false
        dropSuccessTitle = nil

        isError = true
        dropErrorTitle = reason
        errorTask?.cancel()
        errorTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled {
                self.isError = false
                self.dropErrorTitle = nil
            }
        }
    }
}

struct MochiStageView: View {
    @ObservedObject var settings: AppSettings
    var coordinator: TrackingCoordinator? = nil
    var mode: PanelMode? = nil
    let onNavigateToTasks: () -> Void
    let onNavigateToChat: () -> Void

    @StateObject private var mochi = MochiState()

    init(
        settings: AppSettings,
        coordinator: TrackingCoordinator? = nil,
        mode: PanelMode? = nil,
        onNavigateToTasks: @escaping () -> Void,
        onNavigateToChat: @escaping () -> Void
    ) {
        self.settings = settings
        self.coordinator = coordinator
        self.mode = mode
        self.onNavigateToTasks = onNavigateToTasks
        self.onNavigateToChat = onNavigateToChat
        if CommandLine.arguments.contains("--demo-mochi-drag") {
            let m = MochiState()
            m.isDragOver = true
            _mochi = StateObject(wrappedValue: m)
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geo in
                let now = timeline.date.timeIntervalSinceReferenceDate

                // Procedural breath (0.42 Hz = 2.4s cycle)
                let breath = CGFloat(sin(now * 2 * .pi * 0.42))

                let cx = geo.size.width / 2
                let cy = geo.size.height / 2 + (mochi.isHappy ? -4.0 : 1.2 * breath)

                ZStack {
                    // Background dark stage card matching Coucou GCARD (padding horizontal 10, cornerRadius 20)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(hex: 0x141518))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    mochi.isDragOver ? Color(hex: 0x60A5FA) : Color.white.opacity(0.06),
                                    style: mochi.isDragOver ? StrokeStyle(lineWidth: 1.8, dash: [6, 4]) : StrokeStyle(lineWidth: 0.8)
                                )
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 12)

                    // Soft ambient radial glow / halo behind Mochi centered at (cx, cy)
                    RadialGradient(
                        stops: [
                            .init(color: mochi.isDragOver ? Color(hex: 0x60A5FA).opacity(0.50) : (mochi.isHappy ? Color(hex: 0x60A5FA).opacity(0.35) : Color(hex: 0x3B82F6).opacity(0.18)), location: 0),
                            .init(color: mochi.isDragOver ? Color(hex: 0x3B82F6).opacity(0.25) : Color.white.opacity(0.08), location: 0.40),
                            .init(color: Color.clear, location: 0.75)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: mochi.isDragOver ? 125 : 95
                    )
                    .frame(width: mochi.isDragOver ? 250 : 190, height: mochi.isDragOver ? 250 : 190)
                    .position(x: cx, y: cy)
                    .allowsHitTesting(false)

                    // Drop instruction / Scanning / Error / Success pill indicator
                    if mochi.isScanning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(Color(hex: 0x38BDF8))
                            Text(mochi.scanningFilename != nil ? "Memindai \(mochi.scanningFilename!)..." : "Memindai Berkas...")
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(hex: 0x0284C7)))
                        .shadow(color: Color(hex: 0x0284C7).opacity(0.5), radius: 8, y: 3)
                        .position(x: cx, y: cy - 78)
                        .allowsHitTesting(false)
                    } else if mochi.isDragOver {
                        HStack(spacing: 6) {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Lepas Berkas ke Bot")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(hex: 0x2563EB)))
                        .shadow(color: Color(hex: 0x2563EB).opacity(0.5), radius: 8, y: 3)
                        .position(x: cx, y: cy - 78)
                        .allowsHitTesting(false)
                    } else if let error = mochi.dropErrorTitle {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(error)
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0xDC2626)))
                        .shadow(color: Color(hex: 0xDC2626).opacity(0.4), radius: 8, y: 3)
                        .position(x: cx, y: cy - 78)
                        .allowsHitTesting(false)
                    } else if let title = mochi.dropSuccessTitle {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0x059669)))
                        .shadow(color: Color(hex: 0x059669).opacity(0.4), radius: 8, y: 3)
                        .position(x: cx, y: cy - 78)
                        .allowsHitTesting(false)
                    }

                    // Animated 3D robot head from fayazara/robot-heads (MIT License).
                    RobotHeadView(
                        state: mochi.isError ? .error
                            : (mochi.isScanning || mochi.isDragOver ? .searching
                            : (mochi.isHappy ? .happy : .idle)),
                        shape: .rectangle,
                        size: 140,
                        color: "#2563EB",
                        trimColor: "#93A6C8",
                        screenColor: "#E8F2FF",
                        antenna: true,
                        floorShadow: true,
                        speed: 1.0,
                        pokeTrigger: mochi.pokeTrigger,
                        tracksCursor: true
                    )
                    .frame(width: 140, height: 140)
                    .position(x: cx, y: cy)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        mochi.reactToTap()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchDragHoverChanged)) { note in
            let isHovering = note.userInfo?["isHovering"] as? Bool ?? false
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                mochi.isDragOver = isHovering
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchDropScanning)) { note in
            let filename = note.userInfo?["filename"] as? String ?? "berkas"
            mochi.reactToScanning(filename: filename)
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchDropCelebrated)) { note in
            if let title = note.userInfo?["title"] as? String {
                mochi.reactToDrop(title: title)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchDropFailed)) { note in
            let reason = note.userInfo?["reason"] as? String ?? "Format berkas tidak didukung"
            mochi.reactToError(reason: reason)
        }
    }

    // MARK: - Vector Drawing Helpers

    static func drawBody(context: GraphicsContext, cx: CGFloat, cy: CGFloat, hw: CGFloat, hh: CGFloat) {
        var bodyCtx = context
        bodyCtx.translateBy(x: cx, y: cy)

        let bodyPath = Self.superellipse(hw: hw, hh: hh)

        // Drop shadow for subtle 3D depth
        bodyCtx.addFilter(.shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 4))

        // Mochi white gradient fill (#FBFBFC to #E7E9EC)
        let gradient = Gradient(stops: [
            .init(color: Color(red: 251/255, green: 251/255, blue: 252/255), location: 0),
            .init(color: Color(red: 231/255, green: 233/255, blue: 236/255), location: 1)
        ])
        bodyCtx.fill(
            bodyPath,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: hw * 0.5, y: -hh),
                endPoint: CGPoint(x: -hw * 0.5, y: hh)
            )
        )

        // Subtle inner stroke for soft edge definition
        bodyCtx.stroke(bodyPath, with: .color(Color.black.opacity(0.06)), lineWidth: 0.8)
    }

    static func drawLeftHand(context: GraphicsContext, cx: CGFloat, cy: CGFloat, hw: CGFloat, hh: CGFloat, breath: CGFloat, isDragOver: Bool) {
        var handCtx = context
        let hx = cx - hw - 10
        let hy = cy + (isDragOver ? -hh * 0.20 : hh * 0.40) + breath * 1.5
        let r: CGFloat = 8.5

        handCtx.translateBy(x: hx, y: hy)
        let ball = Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))

        handCtx.addFilter(.shadow(color: Color.black.opacity(0.20), radius: 3, x: 0, y: 2))
        handCtx.fill(ball, with: .color(Color(red: 248/255, green: 249/255, blue: 250/255)))
        handCtx.stroke(ball, with: .color(Color.black.opacity(0.06)), lineWidth: 0.6)
    }

    static func drawRightHand(context: GraphicsContext, cx: CGFloat, cy: CGFloat, hw: CGFloat, hh: CGFloat, wave: CGFloat, isHappy: Bool, isDragOver: Bool) {
        var handCtx = context
        let hx = cx + hw + 11
        let hy = cy - hh * (isDragOver ? 0.30 : 0.15)
        let armW: CGFloat = 20
        let armH: CGFloat = 11

        handCtx.translateBy(x: hx, y: hy)
        let baseAngle: CGFloat = isDragOver ? -1.0 : -0.58
        let waveAngle: CGFloat = (isHappy || isDragOver ? 0.22 : 0.10) * wave
        handCtx.rotate(by: .radians(baseAngle + waveAngle))

        let rect = CGRect(x: -armW / 2, y: -armH / 2, width: armW, height: armH)
        let armPath = Path(roundedRect: rect, cornerRadius: armH / 2)

        handCtx.addFilter(.shadow(color: Color.black.opacity(0.20), radius: 3, x: 0, y: 2))
        handCtx.fill(armPath, with: .color(Color(red: 248/255, green: 249/255, blue: 250/255)))
        handCtx.stroke(armPath, with: .color(Color.black.opacity(0.06)), lineWidth: 0.6)
    }

    static func drawEyes(context: GraphicsContext, cx: CGFloat, cy: CGFloat, hw: CGFloat, hh: CGFloat, lookX: CGFloat, lookY: CGFloat, eyeOpen: CGFloat, isHappy: Bool) {
        var eyeCtx = context
        eyeCtx.translateBy(x: cx, y: cy)

        let eyeSpacing: CGFloat = hw * 0.44
        let eyeR: CGFloat = 4.2
        let eyeH: CGFloat = 7.0 * eyeOpen

        // Look offsets clamped
        let lx = lookX * (hw * 0.25)
        let ly = -lookY * (hh * 0.20) + 1.0

        for side: CGFloat in [-1, 1] {
            var singleEyeCtx = eyeCtx
            let ex = side * eyeSpacing + lx
            let ey = ly
            singleEyeCtx.translateBy(x: ex, y: ey)

            if isHappy {
                // Curved happy eye arc `^`
                var arc = Path()
                arc.addArc(
                    center: CGPoint(x: 0, y: 1.5),
                    radius: eyeR * 1.3,
                    startAngle: .degrees(195),
                    endAngle: .degrees(345),
                    clockwise: false
                )
                singleEyeCtx.stroke(arc, with: .color(Color(hex: 0x16171A)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            } else {
                // Vertical dark pill eye (#16171A)
                let rect = CGRect(x: -eyeR, y: -eyeH / 2, width: eyeR * 2, height: eyeH)
                let path = Path(roundedRect: rect, cornerRadius: eyeR)
                singleEyeCtx.fill(path, with: .color(Color(hex: 0x16171A)))
            }
        }
    }

    // MARK: - Superellipse Math (Coucou Lamé Curve)

    static func superellipse(hw: CGFloat, hh: CGFloat) -> Path {
        let n: CGFloat = 3.2
        var p = Path()
        let steps = 96
        for i in 0...steps {
            let a = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let ca = cos(a)
            let sa = sin(a)
            let px = hw * (ca < 0 ? -1 : 1) * pow(abs(ca), 2 / n)
            let py = hh * (sa < 0 ? -1 : 1) * pow(abs(sa), 2 / n)
            if i == 0 {
                p.move(to: CGPoint(x: px, y: py))
            } else {
                p.addLine(to: CGPoint(x: px, y: py))
            }
        }
        p.closeSubpath()
        return p
    }
}

/// Mini Mochi mascot for the collapsed notch capsule.
/// Procedural vector squircle with pupil tracking and blinking.
struct MiniMochiView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.main ?? NSScreen.screens.first!
            let rawLookX = (mouse.x - screen.frame.midX) / 220
            let rawLookY = (mouse.y - (screen.frame.maxY - 18)) / 140
            let lookX = CGFloat(tanh(rawLookX))
            let lookY = CGFloat(tanh(rawLookY))

            let blinkCycle = now.truncatingRemainder(dividingBy: 3.8)
            let eyeOpen: CGFloat = (blinkCycle < 0.14) ? max(0.1, 1.0 - sin(.pi * CGFloat(blinkCycle / 0.14))) : 1.0

            Canvas { context, size in
                let cx = size.width / 2
                let cy = size.height / 2
                let hw: CGFloat = 11.5
                let hh: CGFloat = 8.5
                let body = MochiStageView.superellipse(hw: hw, hh: hh)
                var bCtx = context
                bCtx.translateBy(x: cx, y: cy)
                bCtx.addFilter(.shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1))
                bCtx.fill(body, with: .color(Color(red: 248/255, green: 249/255, blue: 250/255)))

                let eyeSpacing: CGFloat = 4.0
                let eyeR: CGFloat = 1.3
                let eyeH: CGFloat = 2.4 * eyeOpen
                let lx = lookX * 1.8
                let ly = -lookY * 1.2 + 0.2

                for side: CGFloat in [-1, 1] {
                    var eCtx = bCtx
                    let ex = side * eyeSpacing + lx
                    let ey = ly
                    eCtx.translateBy(x: ex, y: ey)
                    let rect = CGRect(x: -eyeR, y: -eyeH / 2, width: eyeR * 2, height: eyeH)
                    eCtx.fill(Path(roundedRect: rect, cornerRadius: eyeR), with: .color(Color(hex: 0x16171A)))
                }
            }
        }
    }
}

/// Full-size animated Mochi mascot view.
///
/// Renders the real Living Icon sprite when the pack is available and falls
/// back to the procedural vector body otherwise. The procedural path is kept
/// because it is the only thing that draws if the pack fails to load, and a
/// Animated 3D robot companion on the inline activity form card.
struct MochiAnimatedHeroView: View {
    var state: RobotHeadState = .happy
    var scale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2

            ZStack {
                // Soft ambient radial glow behind the robot head
                RadialGradient(
                    stops: [
                        .init(color: Color(hex: 0x60A5FA).opacity(state == .happy ? 0.38 : 0.20), location: 0),
                        .init(color: Color(hex: 0x3B82F6).opacity(0.12), location: 0.45),
                        .init(color: Color.clear, location: 0.80)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 85 * scale
                )
                .frame(width: 170 * scale, height: 170 * scale)
                .position(x: cx, y: cy)
                .allowsHitTesting(false)

                RobotHeadView(
                    state: state,
                    shape: .rectangle,
                    size: 104 * scale,
                    color: "#2563EB",
                    trimColor: "#93A6C8",
                    screenColor: "#E8F2FF",
                    antenna: true,
                    floorShadow: false,
                    tracksCursor: true
                )
                .position(x: cx, y: cy)
            }
        }
    }
}
