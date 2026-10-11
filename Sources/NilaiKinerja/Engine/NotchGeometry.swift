import AppKit

/// Notch geometry and the panel layout derived from it.
enum NotchGeometry {

    /// Fallback capsule for displays with no physical cutout (external
    /// monitors, iMac, Mac mini). Roughly the size of a Dynamic Island.
    static let fallbackSize = CGSize(width: 208, height: 37)

    /// The expanded body. Sized to fit the character, the activity list, the
    /// add-activity form, and its document picker without crowding. Generous
    /// on purpose: the panel is read at a glance, so air beats density.
    static let expandedWidth: CGFloat = 520

    /// Chrome around the activity list: header, divider, list padding, and the
    /// add button. The list viewport itself is a *fixed* `maxVisibleRows *
    /// rowPitch` regardless of how many sessions exist, so this is the only
    /// part that varies — and because the list never resizes, neither does the
    /// panel.
    ///
    /// Measured from the running layout, not guessed: header 56, divider 1,
    /// list vertical padding 28, add button 48, plus the gaps between them.
    static let expandedChromeHeight: CGFloat = 118

    /// One activity row plus its bottom margin. Sized for >= 16pt body typography.
    static let rowPitch: CGFloat = 88

    /// Rows shown at once. Beyond this the list scrolls rather than growing the
    /// panel, which is what keeps the hover state a glanceable summary.
    static let maxVisibleRows = 3

    /// The expanded body, hugging however many rows are showing.
    ///
    /// Clamped so an empty or overflowing list cannot collapse the panel to
    /// nothing or push it past the canvas.
    static func expandedSize(rowCount: Int) -> CGSize {
        let rows = min(max(rowCount, 0), maxVisibleRows)
        let height = expandedChromeHeight + CGFloat(rows) * rowPitch
        return CGSize(width: expandedWidth, height: min(height, canvasSize.height))
    }

    /// The tallest the expanded panel can get. The canvas and the hover
    /// hit-region use this, since neither knows the row count.
    static var maxExpandedSize: CGSize {
        expandedSize(rowCount: maxVisibleRows)
    }

    /// Corner radius for the expanded panel. Large enough to read as a soft,
    /// floating surface rather than a hard-edged rectangle.
    static let expandedRadius: CGFloat = 34

    /// The settings panel's own height budget, and the scrollable body inside
    /// it. Settings includes sections for Ukuran, Waktu Kerja, Pengingat,
    /// Hover, Animasi, and Folder Penyimpanan.
    static let settingsHeight: CGFloat = 600
    static let settingsBodyHeight: CGFloat = 490

    /// Dedicated heights for specific screens so the panel hugs its content
    /// exactly without clipping or dead void space.
    static let homeHeight: CGFloat = 265
    static let homeWithFormHeight: CGFloat = 645
    static let emptyListHeight: CGFloat = 255
    static let addFormHeight: CGFloat = 520
    static let editFormHeight: CGFloat = 420
    static let checkpointHeight: CGFloat = 360
    /// Grown by one tab-bar row when the chat adopted the shared notch header,
    /// so the conversation area keeps the room it had before.
    static let chatHeight: CGFloat = 566

    /// The window is a fixed, generously sized canvas anchored to the top of
    /// the display. It never resizes — the notch shape morphs *inside* it.
    ///
    /// This is what makes the expansion fluid. A window that resizes on every
    /// state change snaps, because AppKit frame animation is not spring-driven
    /// and `setFrame(_:display:animate:)` with `animate: false` is instant.
    /// A static canvas lets SwiftUI interpolate width, height and corner radius
    /// with a real spring, which is what reads as "liquid".
    static let canvasSize = CGSize(width: 1200, height: 680)

    struct Metrics {
        /// Physical cutout size of the notch (without overhang).
        /// Used for State 1 (Idle: native MacBook M4 notch with glowing stroke).
        var hardwareNotch: CGSize
        /// Size of the collapsed capsule with overhang (mini mochi & counter).
        /// Used for State 2 (Idle Hover: capsule preview).
        var collapsed: CGSize
        /// True when the display has a real hardware notch. Drives the shape:
        /// a notched display gets straight inner edges (it merges into the
        /// cutout), a notchless one gets a fully rounded pill.
        var isNotched: Bool
        var screen: NSScreen
    }

    /// How far the collapsed capsule overhangs the notch on each side,
    /// expressed as a fraction of the notch width so it scales across
    /// machines (the M4 Air and the 14" MBP have different notch widths).
    ///
    /// At 20% the capsule is noticeably wider than the cutout, which is what
    /// gives the character and the clock room to sit *outside* the notch
    /// rather than being crowded against its edges.
    private static let collapsedOverhangRatio: CGFloat = 0.20

    /// Bottom corner radius of the collapsed capsule, matching the M4 Air's
    /// notch. Deliberately small: a pill-shaped bottom (`height / 2`, i.e.
    /// ~21pt here) reads as a separate floating blob rather than as the
    /// notch itself continuing downward. The hardware uses a subtle break of
    /// roughly 11pt, and matching it is what makes the app look native.
    private static let collapsedRadius: CGFloat = 11

    static func metrics(for screen: NSScreen) -> Metrics {
        // auxiliaryTopLeftArea / auxiliaryTopRightArea are the menu bar regions
        // flanking the cutout. Nil on notchless displays.
        if #available(macOS 12.0, *),
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchWidth = screen.frame.width - (left.width + right.width)
            let height = left.height
            if notchWidth > 0, height > 0 {
                let overhang = notchWidth * collapsedOverhangRatio
                return Metrics(
                    hardwareNotch: CGSize(width: notchWidth, height: height),
                    collapsed: CGSize(
                        width: min(notchWidth + overhang * 2, screen.frame.width - 24),
                        height: height
                    ),
                    isNotched: true,
                    screen: screen
                )
            }
        }
        // Notchless display: no cutout to echo, so a full pill is correct.
        return Metrics(
            hardwareNotch: fallbackSize,
            collapsed: CGSize(
                width: (fallbackSize.width * (1 + collapsedOverhangRatio * 2)).rounded(),
                height: fallbackSize.height
            ),
            isNotched: false,
            screen: screen
        )
    }

    /// Bottom corner radius for the collapsed state. A notched display gets
    /// the hardware-matched break; a notchless one gets a full pill.
    static func collapsedRadius(isNotched: Bool, height: CGFloat) -> CGFloat {
        isNotched ? collapsedRadius : height / 2
    }

    /// The target screen: the built-in display if present, else the main one,
    /// else whatever the mouse is on. Falling back this way means a user who
    /// unplugs the laptop display still gets a working capsule.
    static func preferredScreen() -> NSScreen? {
        let builtin = NSScreen.screens.first { screen in
            guard let id = screen.cgDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
        if let builtin { return builtin }
        if let main = NSScreen.main { return main }

        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.screens.first
    }

    /// The window frame. Fixed size, anchored so the canvas top edge sits one
    /// point above the display's top — the notch then straddles y=0 inside the
    /// canvas, exactly where the hardware cutout is.
    static func canvasFrame(on screen: NSScreen) -> NSRect {
        let x = floor(screen.frame.midX - canvasSize.width / 2)
        let y = screen.frame.maxY - canvasSize.height + 1
        return NSRect(x: x, y: y, width: canvasSize.width, height: canvasSize.height)
    }

    /// Screen-space rect of the shape currently presented. This is the only
    /// region that accepts mouse input; everything else in the canvas must
    /// click through to whatever is underneath.
    ///
    /// Takes the *presented* size rather than deriving one from a constant.
    /// The expanded width is a user setting (360...720 pt), so a derived frame
    /// left the outer strips of the panel outside the hit region — and the
    /// header buttons that live there silently stopped responding to clicks
    /// while the keyboard shortcuts kept working.
    static func presentedFrame(on screen: NSScreen, size: CGSize) -> NSRect {
        let width = max(1, size.width)
        let height = max(1, size.height)
        return NSRect(
            x: floor(screen.frame.midX - width / 2),
            y: screen.frame.maxY - height + 1,
            width: width,
            height: height
        )
    }

    /// Tallest the expanded panel can present, used as the hit-region fallback
    /// before the view has reported a real size.
    static var fallbackExpandedSize: CGSize {
        CGSize(width: expandedWidth, height: settingsHeight)
    }

    /// Awareness zone around the idle notch capsule.
    ///
    /// Calibrated to the immediate proximity of the idle notch so drags elsewhere
    /// on the desktop, Finder, or browser windows never accidentally trigger the panel.
    /// The notch only awakens when a dragged file approaches right near the notch lip.
    static func dropZone(on screen: NSScreen, collapsed: CGSize) -> NSRect {
        presentedFrame(on: screen, size: collapsed).insetBy(dx: -60, dy: -36)
    }
}
