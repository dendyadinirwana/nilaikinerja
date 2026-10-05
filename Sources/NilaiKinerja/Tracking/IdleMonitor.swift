import Foundation
import AppKit
import CoreGraphics

/// Seconds since the last keyboard or mouse event.
///
/// Uses `CGEventSource.secondsSinceLastEventType` rather than
/// `IOHIDGetSecondsSinceLastHIDEvent` — the latter is not exported in the
/// current SDK and would need a private-symbol lookup for no benefit. This
/// reads the same `hidSystemState` counter through public API, needs no
/// entitlement, and cannot break on an OS update.
///
/// This is the signal that keeps a lunch break or an afternoon nap from being
/// billed as eight hours of work — the single biggest source of inflated
/// numbers in a hand-kept timesheet.
@MainActor
final class IdleMonitor {
    /// Idle this long counts as "away" and pauses the timer.
    var threshold: TimeInterval = 300

    /// Poll interval. Two seconds is responsive enough to feel instant and
    /// cheap enough to leave running all day.
    private let pollInterval: TimeInterval = 2
    private var timer: Timer?

    private(set) var idleSeconds: TimeInterval = 0
    private(set) var isIdle: Bool = false

    /// `.anyInputEventType` is spelled as a raw value because Swift's
    /// `CGEventType` has no named constant for it.
    private static let anyInput = CGEventType(rawValue: ~0)!

    func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let seconds = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: Self.anyInput
        )
        idleSeconds = seconds.isFinite ? seconds : 0
        let nowIdle = idleSeconds >= threshold
        // Only report transitions — the timer layer acts on edges, not levels.
        if nowIdle != isIdle {
            isIdle = nowIdle
            onIdleChange?(nowIdle)
        }
    }

    var onIdleChange: ((Bool) -> Void)?
}

/// Suppresses checkpoints while the user is presenting or on a call. Popping a
/// panel over someone's screen share is the fastest way to get an app
/// uninstalled, and it is trivially avoidable.
@MainActor
final class MeetingDetector {
    /// Matched against the localized bundle identifier of running apps.
    /// Deliberately narrow — a false positive silently suppresses the
    /// checkpoint, which is worse than a spurious one.
    private static let meetingBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.rteams",
        "com.google.meet",
        "com.apple.FaceTime",
        "com.hammerandchisel.blackhole",
        "com.tinyspeck.slackmacgap",
        "com.discord",
        "com.openai.Chat",
        "com.anthropic.claude",
        "com.openai.codex",
        "IDEBraveSoftware.Brave-GPU",
        "com.google.Chrome"
    ]

    /// Apps that merely *could* host a meeting (browsers, Slack) only suppress
    /// the checkpoint when they are frontmost, not when merely running.
    private static let needsFrontmost: Set<String> = [
        "com.google.Chrome",
        "com.tinyspeck.slackmacgap",
        "com.discord",
        "com.openai.Chat",
        "com.anthropic.claude",
        "com.openai.codex"
    ]

    /// A fullscreen window is treated as a presentation for this app's
    /// purposes, regardless of which app owns it.
    var isFullscreen: Bool {
        NSScreen.screens.contains { screen in
            SkyLightBridge.shared.isFullscreenSpaceActive(on: screen)
        }
    }

    var isInMeeting: Bool {
        // Never prompt during a fullscreen space — that is a presentation by
        // definition and the safe assumption is to stay quiet.
        if isFullscreen { return true }

        let frontmost = NSWorkspace.shared.frontmostApplication
        let running = NSWorkspace.shared.runningApplications

        let meetingRunning = running.contains { app in
            guard let bid = app.bundleIdentifier,
                  Self.meetingBundleIDs.contains(bid) else { return false }
            return !Self.needsFrontmost.contains(bid)
        }
        if meetingRunning { return true }

        // Comm apps count only when frontmost and in a call window. Requiring
        // frontmost avoids suppressing work just because Slack is open.
        if let bid = frontmost?.bundleIdentifier, Self.needsFrontmost.contains(bid) {
            return true
        }
        return false
    }
}
