import Foundation
import Combine

/// Decides when to show the next checkpoint.
///
/// The naive design — "prompt every 60 minutes" — is what kills habits like
/// this. A prompt the user dismisses twice gets dismissed forever, and the
/// data quietly stops accumulating. So the interval is adaptive: dismissal
/// lengthens it, engagement shortens it, and the range is clamped so it can
/// neither vanish nor nag.
@MainActor
final class AdaptiveTimer: ObservableObject {
    @Published private(set) var nextInterval: TimeInterval
    @Published private(set) var lastEngagedAt: Date?

    private let minimum: TimeInterval = 15 * 60
    private let maximum: TimeInterval = 3 * 60 * 60
    var baseInterval: TimeInterval = 60 * 60 {
        didSet {
            nextInterval = max(minimum, min(maximum, baseInterval))
            if timer != nil { reschedule() }
        }
    }

    private var consecutiveSkips = 0
    private var timer: Timer?

    /// Called when the interval elapses and the user is available.
    var onFire: (() -> Void)?

    init() {
        self.nextInterval = 60 * 60
    }

    func start() {
        guard timer == nil else { return }
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// The user answered the checkpoint.
    func recordEngagement() {
        consecutiveSkips = 0
        lastEngagedAt = Date()
        // Ease back toward the default rather than snapping all the way, so a
        // single tap does not immediately re-prompt.
        nextInterval = max(minimum, min(baseInterval, (nextInterval + baseInterval) / 2))
        reschedule()
    }

    /// The user dismissed the checkpoint without answering.
    func recordSkip() {
        consecutiveSkips += 1
        // 15 → 30 → 60 → 120 min, then hold at the ceiling.
        let escalated = baseInterval * pow(2, Double(min(consecutiveSkips, 4) - 1))
        nextInterval = min(maximum, max(minimum, escalated))
        reschedule()
    }

    /// A meeting or idle period interrupts the wait. Restart the full interval
    /// afterwards so the user is not prompted the instant they sit back down.
    func deferTemporarily() {
        reschedule()
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        schedule()
    }

    private func schedule() {
        let t = Timer(timeInterval: nextInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.timer = nil
                self.onFire?()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Seconds until the next checkpoint, for the settings UI.
    var countdown: TimeInterval { nextInterval }
}
