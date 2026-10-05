import Foundation
import Combine
import AppKit

/// The single place where tracking policy lives: what counts as work, when to
/// prompt, and when to stay silent.
///
/// Every decision that would otherwise be scattered across the UI lives here
/// so the rules are auditable in one file.
@MainActor
final class TrackingCoordinator: ObservableObject {

    enum PanelState: Equatable {
        case collapsed
        case checkpoint
        case paused
    }

    /// Panel visibility. Public so the view layer can open the checkpoint on
    /// a tap; the tracking policy still lives in this class.
    @Published var panelState: PanelState = .collapsed
    @Published private(set) var pausedReason: PausedReason?
    @Published private(set) var now: Date = Date()

    enum PausedReason: String {
        case idle = "Menunggu aktivitas"
        case meeting = "Ada rapat berjalan"

        var display: String {
            switch self {
            case .idle: return "Timer dijeda — tidak ada aktivitas"
            case .meeting: return "Timer dijeda — terdeteksi rapat"
            }
        }
    }

    let store: SessionStore
    let idle = IdleMonitor()
    let meeting = MeetingDetector()
    let timer = AdaptiveTimer()

    /// Drives the elapsed-time label. One second is enough; the display rounds
    /// to minutes anyway.
    private var clock: Timer?
    /// Re-checks meeting state so a call that starts mid-interval is noticed.
    private var meetingPoll: Timer?

    init(store: SessionStore) {
        self.store = store
        wire()
    }

    private func wire() {
        idle.onIdleChange = { [weak self] nowIdle in
            self?.handleIdleChange(nowIdle)
        }
        timer.onFire = { [weak self] in
            self?.handleCheckpointDue()
        }
    }

    // MARK: - Lifecycle

    func start() {
        // Adopt an unfinished session rather than discarding it — a crash
        // mid-task should not erase the hours already logged.
        if store.active == nil {
            store.startSession()
        }
        idle.start()
        applyReminderSettings()
        startClock()
        startMeetingPoll()
    }

    func applyReminderSettings() {
        let settings = AppSettings.shared
        if settings.reminderEnabled {
            timer.baseInterval = TimeInterval(settings.reminderIntervalMinutes * 60)
            timer.start()
        } else {
            timer.stop()
        }
    }

    private func startClock() {
        clock?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        RunLoop.main.add(t, forMode: .common)
        clock = t
    }

    private func startMeetingPoll() {
        meetingPoll?.invalidate()
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcilePause() }
        }
        RunLoop.main.add(t, forMode: .common)
        meetingPoll = t
    }

    // MARK: - Pause policy

    /// Idle or meeting pauses the timer but never ends the session. Resuming
    /// continues the same work, so a ten-minute call does not fragment the log.
    private func reconcilePause() {
        if meeting.isInMeeting {
            pausedReason = .meeting
            if panelState == .checkpoint { panelState = .collapsed }
        } else if idle.isIdle {
            pausedReason = .idle
            if panelState == .checkpoint { panelState = .collapsed }
        } else {
            pausedReason = nil
        }
    }

    private func handleIdleChange(_ nowIdle: Bool) {
        reconcilePause()
        if nowIdle {
            // Push the next checkpoint out; prompting someone who walked away
            // is pure noise.
            timer.deferTemporarily()
        }
    }

    // MARK: - Checkpoint

    private func handleCheckpointDue() {
        guard AppSettings.shared.reminderEnabled else { return }
        guard panelState == .collapsed else { return }
        guard store.active != nil else {
            store.startSession()
            return
        }
        reconcilePause()
        guard pausedReason == nil else {
            // Not a good moment. Try again after another interval.
            timer.deferTemporarily()
            return
        }

        if AppSettings.shared.reminderSoundEnabled {
            if let sound = NSSound(named: "Ping") {
                sound.play()
            } else {
                NSSound.beep()
            }
        }

        panelState = .checkpoint
    }

    /// The user confirmed — the work continues, note the engagement so the
    /// interval can tighten back toward the default.
    func confirm(title: String, detail: String?, outcome: String?) {
        guard let session = store.active else { return }
        store.update(
            sessionID: session.id,
            title: title,
            detail: detail,
            outcome: outcome,
            markRecorded: true
        )
        panelState = .collapsed
        timer.recordEngagement()
    }

    /// The user finished this task and is starting another. The previous one
    /// is closed and a fresh session begins, so elapsed time is never
    /// double-counted across two jobs.
    func switchTask(title: String, detail: String?, outcome: String?) {
        if let session = store.active {
            if !title.trimmingCharacters(in: .whitespaces).isEmpty {
                store.update(
                    sessionID: session.id,
                    title: title,
                    detail: detail,
                    outcome: outcome,
                    markRecorded: true
                )
            }
            store.endSession(cause: .manual)
        }
        store.startSession()
        panelState = .collapsed
        timer.recordEngagement()
    }

    /// Dismissed without answering. The timer keeps running — the work is
    /// almost certainly still happening — but the interval backs off.
    func skip() {
        panelState = .collapsed
        timer.recordSkip()
    }

    func togglePause() {
        guard let session = store.active else { return }
        if session.isRunning {
            store.endSession(cause: .manual)
            panelState = .collapsed
        } else {
            store.startSession()
            panelState = .collapsed
        }
    }

    // MARK: - Attachments

    func attach(_ urls: [URL]) {
        guard let sessionID = store.active?.id else { return }
        for url in urls {
            guard let stored = try? AttachmentStore.store(url) else { continue }
            store.addAttachment(
                sessionID: sessionID,
                filename: stored.filename,
                storedPath: stored.path,
                kind: stored.kind,
                bytes: stored.bytes,
                sha256: stored.sha256
            )
        }
    }

    // MARK: - Reporting

    @discardableResult
    func exportDaily(on date: Date = Date()) throws -> URL {
        let url = ReportBuilder.defaultExportDirectory()
            .appendingPathComponent(ReportBuilder.dailyFilename(for: date))
        try ReportBuilder.daily(on: date, store: store, to: url)
        return url
    }

    @discardableResult
    func exportMonthly() throws -> URL {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
        let url = ReportBuilder.defaultExportDirectory()
            .appendingPathComponent(ReportBuilder.monthlyFilename(for: DateInterval(start: start, end: end)))
        try ReportBuilder.monthly(in: DateInterval(start: start, end: end), store: store, to: url)
        return url
    }

    /// Marks an achievement. The character animation lives in a web view, so
    /// the celebration is driven by the menu bar menu instead of by the
    /// coordinator — this is the seam the add-activity form calls.
    func celebrate() {
        NotificationCenter.default.post(name: .notchCelebrate, object: nil)
    }

    // MARK: - Derived

    var elapsed: TimeInterval {
        store.active?.duration ?? 0
    }

    var elapsedLabel: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
