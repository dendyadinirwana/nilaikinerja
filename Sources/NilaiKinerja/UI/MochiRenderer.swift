import SwiftUI
import CoreGraphics

// ============================================================================
// Mochi renderer — ported from Coucou (https://github.com/Louis-CFM/coucou)
//
// Upstream files: NotchBuddy/Sources/App/BotEngine.swift,
//                 NotchBuddy/Sources/App/MochiOutfitDrawing.swift
// Copyright (c) 2026 Louis Raillé — MIT License (see LICENSE in that repo)
//
// This is a derivative work of Coucou's source code, redistributed under the
// MIT License as required by that license:
//
//   Permission is hereby granted, free of charge, to any person obtaining a
//   copy of this software and associated documentation files (the "Software"),
//   to deal in the Software without restriction, ... THE SOFTWARE IS PROVIDED
//   "AS IS", WITHOUT WARRANTY OF ANY KIND ...
//
// IMPORTANT — CHARACTER RIGHTS
// Coucou's MIT license covers its *source code* but explicitly excludes the
// Mochi character itself (design, look, expressions and animations), which
// remains the property of Louis Raillé. See LICENSE-ASSETS.md upstream.
// This file reproduces that character, so it is for PRIVATE, NON-DISTRIBUTED
// use only. Do not ship it, and do not publish it, in any NilaiKinerja
// build that leaves this machine. If that ever changes, replace the character
// — the engine below is generic; only `MochiConst` and `MochiPoses` carry
// the artwork.
// ============================================================================

// MARK: - Constants

/// Track constants, from Coucou's `MochiConst` (upstream notes them as
/// "from PISTES.mochi"). These are the character's identity — changing them
/// changes Mochi.
enum MochiConst {
    static let eyeW: CGFloat = 0.25
    static let eyeH: CGFloat = 0.27
    static let eyeSp: CGFloat = 0.37
    static let eyeP: CGFloat = -0.12
    static let baseTop = CGColor(red: 0.929, green: 0.929, blue: 0.937, alpha: 1)   // #EDEDEF
    static let baseBottom = CGColor(red: 0.769, green: 0.773, blue: 0.792, alpha: 1) // #C4C5CA
    static let ink = CGColor(red: 0.102, green: 0.082, blue: 0.071, alpha: 1)        // #1A1412
    static let blushColor = Color(red: 1, green: 0.471, blue: 0.588)
}

private let kEXP: CGFloat = 2.7
private let kEYE_W = MochiConst.eyeW
private let kEYE_H = MochiConst.eyeH
private let kEYE_SP = MochiConst.eyeSp
private let kEYE_P = MochiConst.eyeP

// MARK: - State vocabulary

/// Mochi's states, matching Coucou's `BotState`.
enum MochiPose: String, CaseIterable {
    case idle, working, thinking, searching
    case approval, question, error, finished
    case ratelimit, sleeping, dizzy
}

/// Transient emotes, matching Coucou's `BotEmote`.
enum MochiEmote: String {
    case love, surprised, proud, wink, yawn, happy, annoyed
}

enum MochiEye: String {
    case pill, wide, dot, line, flat, happy, closed, spiral, heart, star, tired, wink
}

enum MochiBadge {
    case dots(CGColor)
    case bang(CGColor)
    case question(CGColor)
    case dot(CGColor)
}

struct MochiCfg {
    var color: CGColor
    var tint: CGFloat
    var eye: MochiEye
    var badge: MochiBadge?
    var badgeColor: CGColor
    var glow: CGColor
    var glowOpacity: CGFloat
    var bounces: Bool
    var scans: Bool
    var breathes: Bool
    var zz: Bool
    var sweat: Bool
    var look: CGPoint?
    var tilt: CGFloat
}

/// Per-state configuration, ported verbatim from Coucou's `BotStates` table.
/// The colors are the reason Mochi reads as "alert amber" versus "calm grey"
/// at a glance, so they are not a place to rebrand.
enum MochiPoses {
    static let table: [MochiPose: MochiCfg] = [
        .idle: MochiCfg(
            color: CGColor(red: 0.902, green: 0.914, blue: 0.933, alpha: 1), tint: 0,
            eye: .pill, badge: nil, badgeColor: .white,
            glow: CGColor(red: 1, green: 1, blue: 1, alpha: 0.35), glowOpacity: 0.25,
            bounces: false, scans: false, breathes: false, zz: false, sweat: false,
            look: nil, tilt: 0),
        .working: MochiCfg(
            color: CGColor(red: 0.231, green: 0.620, blue: 1, alpha: 1), tint: 0.72,
            eye: .pill, badge: .dots(CGColor(red: 0.231, green: 0.620, blue: 1, alpha: 1)),
            badgeColor: CGColor(red: 0.231, green: 0.620, blue: 1, alpha: 1),
            glow: CGColor(red: 0.231, green: 0.620, blue: 1, alpha: 1), glowOpacity: 0.55,
            bounces: false, scans: false, breathes: false, zz: false, sweat: false,
            look: nil, tilt: 0),
        .thinking: MochiCfg(
            color: CGColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 1), tint: 0.72,
            eye: .pill, badge: .dots(CGColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 1)),
            badgeColor: CGColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 1),
            glow: CGColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 1), glowOpacity: 0.5,
            bounces: false, scans: false, breathes: false, zz: false, sweat: false,
            look: CGPoint(x: 0.55, y: 0.55), tilt: 0),
        .searching: MochiCfg(
            color: CGColor(red: 0.388, green: 0.396, blue: 0.949, alpha: 1), tint: 0.72,
            eye: .pill, badge: .dots(CGColor(red: 0.388, green: 0.396, blue: 0.949, alpha: 1)),
            badgeColor: CGColor(red: 0.388, green: 0.396, blue: 0.949, alpha: 1),
            glow: CGColor(red: 0.388, green: 0.396, blue: 0.949, alpha: 1), glowOpacity: 0.55,
            bounces: false, scans: true, breathes: false, zz: false, sweat: false,
            look: nil, tilt: 0),
        .approval: MochiCfg(
            color: CGColor(red: 0.961, green: 0.647, blue: 0.141, alpha: 1), tint: 0.78,
            eye: .wide, badge: .bang(CGColor(red: 0.961, green: 0.647, blue: 0.141, alpha: 1)),
            badgeColor: CGColor(red: 0.961, green: 0.647, blue: 0.141, alpha: 1),
            glow: CGColor(red: 0.961, green: 0.647, blue: 0.141, alpha: 1), glowOpacity: 0.6,
            bounces: true, scans: false, breathes: false, zz: false, sweat: false,
            look: nil, tilt: 0),
        .question: MochiCfg(
            color: CGColor(red: 0.133, green: 0.827, blue: 0.933, alpha: 1), tint: 0.75,
            eye: .pill, badge: .question(CGColor(red: 0.133, green: 0.827, blue: 0.933, alpha: 1)),
            badgeColor: CGColor(red: 0.133, green: 0.827, blue: 0.933, alpha: 1),
            glow: CGColor(red: 0.133, green: 0.827, blue: 0.933, alpha: 1), glowOpacity: 0.55,
            bounces: false, scans: false, breathes: false, zz: false, sweat: false,
            look: nil, tilt: 0.17),
        .error: MochiCfg(
            color: CGColor(red: 0.957, green: 0.314, blue: 0.369, alpha: 1), tint: 0.78,
            eye: .flat, badge: .dot(CGColor(red: 0.957, green: 0.314, blue: 0.369, alpha: 1)),
            badgeColor: CGColor(red: 0.957, green: 0.314, blue: 0.369, alpha: 1),
            glow: CGColor(red: 0.957, green: 0.314, blue: 0.369, alpha: 1), glowOpacity: 0.55,
            bounces: false, scans: false, breathes: false, zz: false, sweat: false,
            look: nil, tilt: 0),
        .finished: MochiCfg(
            color: CGColor(red: 0.204, green: 0.831, blue: 0.600, alpha: 1), tint: 0.35,
            eye: .happy, badge: .dot(CGColor(red: 0.204, green: 0.831, blue: 0.600, alpha: 1)),
            badgeColor: CGColor(red: 0.204, green: 0.831, blue: 0.600, alpha: 1),
            glow: CGColor(red: 0.204, green: 0.831, blue: 0.600, alpha: 1), glowOpacity: 0.5,
            bounces: false, scans: false, breathes: false, zz: false, sweat: false,
            look: nil, tilt: 0),
        .ratelimit: MochiCfg(
            color: CGColor(red: 0.984, green: 0.573, blue: 0.235, alpha: 1), tint: 0.72,
            eye: .tired, badge: .dot(CGColor(red: 0.984, green: 0.573, blue: 0.235, alpha: 1)),
            badgeColor: CGColor(red: 0.984, green: 0.573, blue: 0.235, alpha: 1),
            glow: CGColor(red: 0.984, green: 0.573, blue: 0.235, alpha: 1), glowOpacity: 0.45,
            bounces: false, scans: false, breathes: false, zz: false, sweat: true,
            look: nil, tilt: 0),
        .sleeping: MochiCfg(
            color: CGColor(red: 0.580, green: 0.635, blue: 0.722, alpha: 1), tint: 0.32,
            eye: .closed, badge: nil, badgeColor: .white,
            glow: CGColor(red: 0.580, green: 0.635, blue: 0.722, alpha: 1), glowOpacity: 0.2,
            bounces: false, scans: false, breathes: true, zz: true, sweat: false,
            look: nil, tilt: 0),
        .dizzy: MochiCfg(
            color: CGColor(red: 0.957, green: 0.447, blue: 0.714, alpha: 1), tint: 0.7,
            eye: .spiral, badge: nil, badgeColor: .white,
            glow: CGColor(red: 0.957, green: 0.447, blue: 0.714, alpha: 1), glowOpacity: 0.55,
            bounces: false, scans: false, breathes: false, zz: false, sweat: false,
            look: nil, tilt: 0),
    ]
}

// MARK: - Head geometry

struct MochiHead {
    let R, rx, ry: CGFloat
    let yaw, pitch, roll: CGFloat

    init(R: CGFloat, yaw: CGFloat = 0, pitch: CGFloat = 0, roll: CGFloat = 0) {
        self.R = R
        self.rx = R * 1.14
        self.ry = R * 0.88
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }
}

struct EyeFrame {
    let sd: CGFloat
    let x, y: CGFloat
    let fx, fy: CGFloat
    let visible: Bool
    let w, h: CGFloat
}

/// Eye placement on the curved body. Ported from `mEyeFrames`.
/// The `cos(eyeYaw) * cos(eyePitch) > 0.04` visibility test is what makes an
/// eye slide off the silhouette as the head turns, instead of floating on top
/// of the body like a sticker.
func mochiEyeFrames(_ H: MochiHead) -> [EyeFrame] {
    var out: [EyeFrame] = []
    for sdD: Double in [-1.0, 1.0] {
        let sd = CGFloat(sdD)
        let eyeYaw = sd * kEYE_SP + H.yaw
        let eyePitch = kEYE_P + H.pitch
        let cp = cos(eyePitch)
        let visible = cos(eyeYaw) * cp > 0.04
        out.append(EyeFrame(
            sd: sd,
            x: sin(eyeYaw) * cp * H.rx,
            y: -sin(eyePitch) * H.ry,
            fx: max(0.18, cos(eyeYaw)),
            fy: max(0.18, cp),
            visible: visible,
            w: H.R * kEYE_W,
            h: H.R * kEYE_H
        ))
    }
    return out
}

// MARK: - Engine

/// Animated character state.
///
/// Every animated scalar eases toward its target with a time-based smoothing
/// factor rather than a fixed per-frame increment: `1 - exp(-dt/tau)` is
/// frame-rate independent, so the character moves identically on a 60Hz
/// external display and a 120Hz ProMotion panel. A fixed increment makes the
/// spring look different on each machine.
@MainActor
final class MochiEngine: ObservableObject {
    var state: MochiPose = .idle { didSet { if state != oldValue { bumpOnStateChange = 1 } } }
    var emote: MochiEmote?

    /// Normalised look target in -1...1. Set by the view from the mouse.
    var lookTarget: CGPoint = .zero
    /// When set, overrides the mouse (used by the capsule, where there is no
    /// meaningful cursor relationship at 20pt).
    var fixedLook: CGPoint?

    // Eased values
    var tint: CGFloat = 0
    var open: CGFloat = 1
    var blush: CGFloat = 0
    var sx: CGFloat = 1
    var sy: CGFloat = 1
    var oy: CGFloat = 0
    var ox: CGFloat = 0
    var tilt: CGFloat = 0
    var badgeS: CGFloat = 0
    var glowOpacity: CGFloat = 0.25
    var yaw: CGFloat = 0
    var pitch: CGFloat = 0
    var roll: CGFloat = 0
    var eyeScale: CGFloat = 1
    var stateColor: CGColor = MochiPoses.table[.idle]!.color

    /// One-shot pop when the state changes, so a transition is felt and not
    /// just seen.
    var bumpOnStateChange: CGFloat = 0

    private var blinkPhase: Double = 0
    private var blinkNext: Double = 2.0

    /// Previous tick's timestamp, kept on the engine because this build cannot
    /// expand the SwiftUI `@State` macro and a Canvas closure cannot mutate the
    /// enclosing view.
    var lastNow: Double = 0

    var cfg: MochiCfg { MochiPoses.table[state] ?? MochiPoses.table[.idle]! }

    /// Eye shape actually drawn: an emote overrides the state's shape while it
    /// is active, which is how Coucou lets a proud face interrupt a working
    /// face without changing state.
    var effectiveEye: MochiEye {
        guard let emote else { return cfg.eye }
        switch emote {
        case .love: return .heart
        case .surprised: return .dot
        case .proud: return .star
        case .wink: return .wink
        case .yawn: return .tired
        case .happy: return .happy
        case .annoyed: return .line
        }
    }

    // MARK: Tick

    func tick(dt: CGFloat, now: Double) {
        let c = cfg
        // tau ~ 0.12s: snappy enough to feel responsive, soft enough to read
        // as a character rather than a state change.
        let k = 1 - exp(-dt / 0.12)
        func ease(_ v: inout CGFloat, _ target: CGFloat) {
            v += (target - v) * k
        }

        ease(&tint, c.tint)
        ease(&glowOpacity, c.glowOpacity)
        ease(&tilt, c.tilt)
        ease(&badgeS, c.badge == nil ? 0 : 1)
        ease(&eyeScale, 1)

        // Blush is not a per-state constant: it rides on tint, plus the emote.
        var blushTarget = c.tint * 0.5
        if emote == .love || emote == .happy { blushTarget = 1 }
        ease(&blush, blushTarget)

        // State colour crossfade
        stateColor = lerpColor(stateColor, c.color, CGFloat(k))

        // Look: mouse, fixed override, or the state's authored gaze.
        var target = c.look ?? lookTarget
        if let fixedLook { target = fixedLook }
        ease(&yaw, clamp(target.x, -1, 1) * 0.34)
        ease(&pitch, -clamp(target.y, -1, 1) * 0.20)

        // Blink. Skipped when the state's eye shape is already closed — a blink
        // on top of sleeping eyes is a no-op that costs a frame of work and
        // looks like a glitch.
        let eyeClosedByState = (effectiveEye == .closed)
        if eyeClosedByState {
            open = 1
        } else {
            blinkPhase += dt
            if blinkPhase > blinkNext {
                blinkNext = blinkPhase + 2.4 + Double.random(in: 0...2.6)
                blinkPhase = 0
            }
            let p = blinkPhase
            open = p < 0.13 ? max(0.06, 1 - sin(.pi * CGFloat(p / 0.13)) * 0.95) : 1
        }

        // Procedural motion
        var oyT: CGFloat = 0
        var syT: CGFloat = 1
        var oxT: CGFloat = 0
        var rollT: CGFloat = 0

        if c.bounces {
            // One bounce per 1.1s, decaying — an approval hop, not a metronome.
            let beat = (now.truncatingRemainder(dividingBy: 1.1)) / 1.1
            let hop = max(0, sin(beat * .pi))
            oyT = -0.30 * hop * hop
            syT = 1 + 0.05 * sin(beat * .pi * 2)
        }
        if c.breathes {
            let br = CGFloat(sin(now * 2 * .pi * 0.34))
            syT = 1 + 0.035 * br
            sx = 1 - 0.020 * br
        } else {
            ease(&sx, 1)
        }
        if c.scans {
            // Head sweeps side to side while searching.
            let sweep = CGFloat(sin(now * 2 * .pi * 0.55))
            yaw += sweep * 0.22
            rollT = sweep * 0.05
        }
        if c.sweat {
            oxT = CGFloat(sin(now * 9)) * 0.012
        }

        // State-change pop: a brief squash-stretch that decays on its own.
        if bumpOnStateChange > 0.001 {
            bumpOnStateChange = max(0, bumpOnStateChange - dt / 0.28)
            let b = bumpOnStateChange
            syT *= 1 + 0.10 * b
            sx *= 1 - 0.07 * b
            oyT -= 0.06 * b
        }

        ease(&oy, oyT)
        ease(&ox, oxT)
        if c.bounces || c.breathes { sy = syT }
        else { ease(&sy, syT) }
        ease(&roll, rollT)
    }

    // MARK: Draw

    func draw(context: GraphicsContext, size: CGSize, now: Double) {
        let W = size.width, H = size.height
        let R = W * 0.3
        let rx = R * 1.14
        let ry = R * 0.88
        let cx = W / 2 + ox * R
        let cy = H / 2 + oy * R + R * 0.06

        var ctx = context
        ctx.translateBy(x: cx, y: cy)
        if tilt != 0 { ctx.rotate(by: .radians(tilt)) }
        ctx.rotate(by: .radians(roll))
        ctx.scaleBy(x: sx, y: sy)

        // Glow, drawn behind the body in body space.
        drawGlow(ctx: &ctx, R: R)

        let bodyPath = mochiPath(rx: rx, ry: ry)
        drawBody(ctx: &ctx, path: bodyPath, R: R, rx: rx, ry: ry)

        let blushVal = max(blush, tint * 0.5)
        if blushVal > 0.01 {
            drawBlush(ctx: &ctx, path: bodyPath, rx: rx, ry: ry, R: R, blush: blushVal)
        }

        drawEyes(ctx: &ctx, path: bodyPath, R: R, rx: rx, ry: ry, now: now)

        if cfg.zz {
            drawZZ(ctx: &ctx, R: R, now: now)
        }
        if cfg.sweat {
            drawSweat(ctx: &ctx, R: R, now: now)
        }
    }

    // MARK: Path

    /// The superellipse that gives Mochi its squishy silhouette.
    /// Ported from `mochiPath` with the mailbox morph dropped — NilaiKinetics has
    /// no upload-bucket morph, so `morph` is pinned at 0 here.
    private func mochiPath(rx: CGFloat, ry: CGFloat) -> Path {
        let n = 72
        let expN: CGFloat = 2.0 / kEXP
        var path = Path()
        for i in 0...n {
            let a = CGFloat(i) / CGFloat(n) * .pi * 2
            let ca = cos(a), sa = sin(a)
            let px = rx * (ca >= 0 ? pow(ca, expN) : -pow(-ca, expN))
            let py = ry * (sa >= 0 ? pow(sa, expN) : -pow(-sa, expN))
            if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
            else { path.addLine(to: CGPoint(x: px, y: py)) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: Body

    private func drawGlow(ctx: inout GraphicsContext, R: CGFloat) {
        let c = cfg
        ctx.fill(Path(ellipseIn: CGRect(x: -R * 1.7, y: -R * 1.7, width: R * 3.4, height: R * 3.4)),
                 with: .radialGradient(
                    Gradient(colors: [Color(cgColor: c.glow).opacity(Double(glowOpacity)),
                                      Color(cgColor: c.glow).opacity(0)]),
                    center: .zero, startRadius: 0, endRadius: R * 1.7
                 ))
    }

    /// Four stacked fills make the body read as soft and lit rather than as a
    /// flat shape: base gradient, state tint, shadow rim, specular highlight.
    private func drawBody(ctx: inout GraphicsContext, path: Path, R: CGFloat, rx: CGFloat, ry: CGFloat) {
        ctx.fill(path, with: .linearGradient(
            Gradient(colors: [Color(cgColor: MochiConst.baseTop), Color(cgColor: MochiConst.baseBottom)]),
            startPoint: CGPoint(x: rx * 0.7, y: -ry * 0.85),
            endPoint: CGPoint(x: -rx * 0.8, y: ry * 0.9)
        ))
        if tint > 0.01 {
            ctx.fill(path, with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(cgColor: stateColor).opacity(Double(0.72 * tint)), location: 0),
                    .init(color: Color(cgColor: stateColor).opacity(0), location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: ry),
                endPoint: CGPoint(x: 0, y: -ry)
            ))
        }
        ctx.fill(path, with: .radialGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.6),
                .init(color: Color.black.opacity(0.2), location: 1)
            ]),
            center: .zero, startRadius: R * 0.15, endRadius: R * 1.25
        ))
        ctx.fill(path, with: .radialGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(0.55), location: 0),
                .init(color: .clear, location: 1)
            ]),
            center: CGPoint(x: rx * 0.34, y: -ry * 0.46),
            startRadius: 0, endRadius: R * 0.42
        ))
    }

    private func drawBlush(ctx: inout GraphicsContext, path: Path, rx: CGFloat, ry: CGFloat, R: CGFloat, blush: CGFloat) {
        ctx.clip(to: path)
        let yOffset = sin(yaw) * rx * 0.8
        for sd in [-1.0, 1.0] {
            let bx = CGFloat(sd) * rx * 0.55 + yOffset
            let by = ry * 0.2
            var ellipse = Path()
            ellipse.addEllipse(in: CGRect(x: bx - R * 0.17, y: by - R * 0.1, width: R * 0.34, height: R * 0.2))
            ctx.fill(ellipse, with: .color(MochiConst.blushColor.opacity(Double(0.5 * blush))))
        }
    }

    // MARK: Eyes

    private func drawEyes(ctx: inout GraphicsContext, path: Path, R: CGFloat, rx: CGFloat, ry: CGFloat, now: Double) {
        let shape = effectiveEye
        let H = MochiHead(R: R, yaw: yaw, pitch: pitch, roll: roll)
        for f in mochiEyeFrames(H) where f.visible {
            var eyePitch = kEYE_P + pitch + roll
            eyePitch = ((eyePitch + .pi).truncatingRemainder(dividingBy: .pi * 2) + .pi * 2)
                .truncatingRemainder(dividingBy: .pi * 2) - .pi
            let cp = cos(eyePitch)
            let eyeYaw = f.sd * kEYE_SP + yaw
            guard cos(eyeYaw) * cp > 0.04 else { continue }

            var eyeCtx = ctx
            eyeCtx.translateBy(x: f.x, y: f.y)
            eyeCtx.scaleBy(x: f.fx, y: f.fy)
            drawEyeShape(ctx: &eyeCtx, shape: shape,
                         w: R * kEYE_W * eyeScale, h: R * kEYE_H * eyeScale,
                         open: open, sd: f.sd, now: now)
        }
    }

    private func drawEyeShape(ctx: inout GraphicsContext, shape: MochiEye, w: CGFloat, h: CGFloat,
                              open: CGFloat, sd: CGFloat, now: Double) {
        let ink = Color(cgColor: MochiConst.ink)

        switch shape {
        case .wide:
            drawEyeShape(ctx: &ctx, shape: .pill, w: w * 1.16, h: h * 1.12, open: open, sd: sd, now: now)

        case .pill:
            let hh = max(h * open, w * 0.3)
            var p = Path()
            p.addRoundedRect(in: CGRect(x: -w / 2, y: -hh / 2, width: w, height: hh),
                             cornerSize: CGSize(width: min(w / 2, hh / 2), height: min(w / 2, hh / 2)))
            ctx.fill(p, with: .color(ink))

        case .dot:
            var p = Path()
            p.addEllipse(in: CGRect(x: -w * 0.45, y: -w * 0.45, width: w * 0.9, height: w * 0.9))
            ctx.fill(p, with: .color(ink))

        case .line:
            ctx.rotate(by: .radians(-sd * 0.2))
            var p = Path()
            p.addRoundedRect(in: CGRect(x: -w * 0.78, y: -w * 0.21, width: w * 1.56, height: w * 0.42),
                             cornerSize: CGSize(width: w * 0.21, height: w * 0.21))
            ctx.fill(p, with: .color(ink))

        case .flat:
            var p = Path()
            p.addRoundedRect(in: CGRect(x: -w * 0.72, y: -h * 0.2, width: w * 1.44, height: h * 0.4),
                             cornerSize: CGSize(width: w * 0.2, height: w * 0.2))
            ctx.fill(p, with: .color(ink))

        case .happy:
            var p = Path()
            p.addArc(center: CGPoint(x: 0, y: h * 0.18), radius: w * 0.82,
                     startAngle: .degrees(180 + 12), endAngle: .degrees(180 - 12), clockwise: true)
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w * 0.5, lineCap: .round))

        case .closed:
            var p = Path()
            p.addArc(center: CGPoint(x: 0, y: -h * 0.08), radius: w * 0.78,
                     startAngle: .degrees(15), endAngle: .degrees(165), clockwise: false)
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w * 0.36, lineCap: .round))

        case .spiral:
            var p = Path()
            var a: CGFloat = 0
            while a < 4.4 * .pi {
                let r = w * 0.06 + a * w * 0.058
                let aa = a + CGFloat(now) * 9 * sd
                let px = cos(aa) * r
                let py = sin(aa) * r
                if a == 0 { p.move(to: CGPoint(x: px, y: py)) }
                else { p.addLine(to: CGPoint(x: px, y: py)) }
                a += 0.2
            }
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w * 0.22, lineCap: .round))

        case .heart:
            ctx.fill(mochiHeartShape(size: w * 1.2), with: .color(Color(red: 1, green: 0.302, blue: 0.427)))

        case .star:
            ctx.rotate(by: .radians(CGFloat(now) * 1.5 * sd))
            ctx.fill(mochiStarShape(outer: w * 1.05, inner: w * 0.46), with: .color(Color(red: 0.969, green: 0.702, blue: 0.169)))

        case .tired:
            var p1 = Path()
            p1.addRoundedRect(in: CGRect(x: -w / 2, y: -h * 0.02, width: w, height: h * 0.38),
                              cornerSize: CGSize(width: w / 2, height: w / 2))
            ctx.fill(p1, with: .color(ink))
            var p2 = Path()
            p2.addRoundedRect(in: CGRect(x: -w * 0.62, y: -h * 0.1, width: w * 1.24, height: w * 0.22),
                              cornerSize: CGSize(width: w * 0.11, height: w * 0.11))
            ctx.fill(p2, with: .color(ink))

        case .wink:
            if sd < 0 {
                let hh = max(h * open, w * 0.3)
                var p = Path()
                p.addRoundedRect(in: CGRect(x: -w / 2, y: -hh / 2, width: w, height: hh),
                                 cornerSize: CGSize(width: min(w / 2, hh / 2), height: min(w / 2, hh / 2)))
                ctx.fill(p, with: .color(ink))
            } else {
                var p = Path()
                p.addArc(center: CGPoint(x: 0, y: h * 0.18), radius: w * 0.82,
                         startAngle: .degrees(180 + 12), endAngle: .degrees(180 - 12), clockwise: true)
                ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w * 0.5, lineCap: .round))
            }
        }
    }

    // MARK: Extras

    private func drawZZ(ctx: inout GraphicsContext, R: CGFloat, now: Double) {
        // Three z's rising and fading, phase-offset so they do not pop in
        // synchronously.
        for i in 0..<3 {
            let phase = (CGFloat(now) * 0.5 - CGFloat(i) * 0.33).truncatingRemainder(dividingBy: 1)
            if phase < 0 { continue }
            let alpha = 0.65 * (1 - phase)
            let scale = 0.5 + 0.5 * phase
            let zx = R * 0.72 + phase * R * 0.25
            let zy = -R * 0.72 - phase * R * 0.45
            var c = ctx
            c.opacity = Double(alpha)
            c.translateBy(x: zx, y: zy)
            c.scaleBy(x: scale, y: scale)
            let s = R * 0.3
            var p = Path()
            p.move(to: CGPoint(x: -s * 0.5, y: -s * 0.5))
            p.addLine(to: CGPoint(x: s * 0.5, y: -s * 0.5))
            p.addLine(to: CGPoint(x: -s * 0.5, y: s * 0.5))
            p.addLine(to: CGPoint(x: s * 0.5, y: s * 0.5))
            c.stroke(p, with: .color(Color(cgColor: cfg.glow)),
                     style: StrokeStyle(lineWidth: R * 0.055, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawSweat(ctx: inout GraphicsContext, R: CGFloat, now: Double) {
        // A droplet that slides down the temple and fades, then restarts.
        let phase = CGFloat(now.truncatingRemainder(dividingBy: 1.6)) / 1.6
        let dropR = R * 0.085
        let dx = R * 0.66
        let dy = -R * 0.34 + phase * R * 0.5
        ctx.opacity = Double(0.7 * (1 - phase))
        var p = Path()
        p.addEllipse(in: CGRect(x: dx - dropR, y: dy - dropR * 1.25, width: dropR * 2, height: dropR * 2.5))
        ctx.fill(p, with: .color(Color(cgColor: cfg.color)))
    }

    // MARK: Badge

    func drawBadge(context: GraphicsContext, size: CGSize) {
        guard let badge = cfg.badge, badgeS > 0.01 else { return }
        let W = size.width, H = size.height
        let R = W * 0.3
        let bs = badgeS
        var ctx = context
        ctx.translateBy(x: W / 2 + ox * R - R * 0.72 * sx,
                        y: H / 2 + oy * R + R * 0.06 - R * 0.72 * sy)
        ctx.scaleBy(x: bs, y: bs)
        let now = CGFloat(CACurrentMediaTime())

        switch badge {
        case .dots(let col):
            let pw: CGFloat = R * 0.72
            let ph: CGFloat = R * 0.36
            var pill = Path()
            pill.addRoundedRect(in: CGRect(x: -pw / 2, y: -ph / 2, width: pw, height: ph),
                                cornerSize: CGSize(width: ph / 2, height: ph / 2))
            ctx.fill(pill, with: .color(Color(cgColor: col)))
            for i in 0..<3 {
                let phase = ((now * 2.4 - CGFloat(i) * 0.22).truncatingRemainder(dividingBy: 1) + 1)
                    .truncatingRemainder(dividingBy: 1)
                let dotR = R * 0.055 * (1 + 0.4 * max(0, sin(phase * .pi * 2)))
                var dot = Path()
                dot.addEllipse(in: CGRect(x: (CGFloat(i) - 1) * R * 0.18 - dotR, y: -dotR,
                                          width: dotR * 2, height: dotR * 2))
                ctx.fill(dot, with: .color(.white))
            }

        case .bang(let col), .question(let col):
            var ring = Path()
            ring.addEllipse(in: CGRect(x: -R * 0.3, y: -R * 0.3, width: R * 0.6, height: R * 0.6))
            ctx.fill(ring, with: .color(.black))
            var inner = Path()
            inner.addEllipse(in: CGRect(x: -R * 0.23, y: -R * 0.23, width: R * 0.46, height: R * 0.46))
            ctx.fill(inner, with: .color(Color(cgColor: col)))
            let text: String
            if case .bang = badge { text = "!" } else { text = "?" }
            ctx.draw(Text(text).font(.system(size: R * 0.32, weight: .black)).foregroundColor(.white),
                     at: CGPoint(x: 0, y: R * 0.02))

        case .dot(let col):
            var outer = Path()
            outer.addEllipse(in: CGRect(x: -R * 0.2, y: -R * 0.2, width: R * 0.4, height: R * 0.4))
            ctx.fill(outer, with: .color(.black))
            var inner = Path()
            inner.addEllipse(in: CGRect(x: -R * 0.135, y: -R * 0.135, width: R * 0.27, height: R * 0.27))
            ctx.fill(inner, with: .color(Color(cgColor: col)))
        }
    }
}

// MARK: - Shape helpers

func mochiHeartShape(size s: CGFloat) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 0, y: s * 0.38))
    p.addCurve(to: CGPoint(x: 0, y: -s * 0.38),
               control1: CGPoint(x: -s * 1.05, y: -s * 0.15),
               control2: CGPoint(x: -s * 0.5, y: -s * 0.95))
    p.addCurve(to: CGPoint(x: 0, y: s * 0.38),
               control1: CGPoint(x: s * 0.5, y: -s * 0.95),
               control2: CGPoint(x: s * 1.05, y: -s * 0.15))
    p.closeSubpath()
    return p
}

func mochiStarShape(outer ro: CGFloat, inner ri: CGFloat) -> Path {
    var p = Path()
    for i in 0..<10 {
        let r = i.isMultiple(of: 2) ? ro : ri
        let a = -.pi / 2 + CGFloat(i) * .pi / 5
        let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

/// Component-wise colour interpolation. CGColor has no built-in lerp, and
/// snapping between state colours makes Mochi flicker on every transition.
func lerpColor(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
    func comp(_ c: CGColor, _ i: Int, _ fallback: CGFloat) -> CGFloat {
        guard let v = c.components?[i] else { return fallback }
        return CGFloat(v)
    }
    let n = max(a.numberOfComponents, b.numberOfComponents)
    var out: [CGFloat] = []
    for i in 0..<n {
        out.append(comp(a, i, 0) + (comp(b, i, 0) - comp(a, i, 0)) * t)
    }
    return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: out) ?? a
}

// MARK: - SwiftUI view

/// The character, driven by a display-linked timeline.
///
/// `TimelineView(.animation)` is what makes this move: SwiftUI redraws it on
/// every display refresh, and the engine eases between states inside each
/// tick. Without it there is nothing to redraw and the character freezes on its
/// first frame — which is exactly the failure the old procedural Canvas had.
struct MochiView: View {
    var state: MochiPose
    var emote: MochiEmote?
    var side: CGFloat
    /// Pin the gaze instead of tracking the cursor. Used at capsule size, where
    /// eye-tracking at 20pt is noise.
    var fixedLook: CGPoint?
    /// Track the mouse. Off by default for the same reason as `fixedLook`.
    var tracksMouse: Bool = false

    @StateObject private var engine = MochiEngine()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                // First frame has no previous timestamp; seeding it here (rather
                // than defaulting dt to 0) is what stops a visible jump on the
                // very first tick. The stamp lives on the engine, not in a
                // `@State`: this build cannot expand the SwiftUI `@State`
                // property-wrapper macro, and a Canvas closure cannot mutate
                // `self` anyway.
                let dt = engine.lastNow == 0 ? 1.0 / 60.0 : min(0.05, now - engine.lastNow)
                engine.lastNow = now

                engine.state = state
                engine.emote = emote
                engine.fixedLook = fixedLook
                if tracksMouse {
                    let m = NSEvent.mouseLocation
                    let screen = NSScreen.screens.first
                    let mw = m.x - (screen?.frame.midX ?? 0)
                    let mh = m.y - (screen?.frame.midY ?? 0)
                    engine.lookTarget = CGPoint(x: clamp(CGFloat(mw / 260), -1, 1),
                                                y: clamp(CGFloat(mh / 200), -1, 1))
                }
                engine.tick(dt: CGFloat(dt), now: now)
                engine.draw(context: ctx, size: size, now: now)
                engine.drawBadge(context: ctx, size: size)
            }
        }
        .frame(width: side, height: side)
        .fixedSize()
    }
}