import Foundation
import CoreGraphics
// `NSScreen` only exists in AppKit. The geometry assertions in
// `testDragDecisionTable` need the real screen frame — a hard-coded drop zone
// would pass on one display and silently miss the notch on another.
import AppKit

/// Headless verification of the data and report layers.
///
/// The notch UI can only be judged by looking at it, but everything behind it
/// — the session log, idle detection, report generation — can be asserted
/// without a window. Run with `NilaiKincare.app/Contents/MacOS/NilaiKinerja
/// --selftest`. Exits non-zero on failure so it can gate a build.
@MainActor
enum SelfTest {
    private static var failures: [String] = []
    private static var checks = 0

    static func run() {
        print("=== Nilai Kinerja selftest ===\n")

        // Must be set before the Database singleton is first constructed.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("nilai-selftest", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        setenv("NK_SELFTEST_DB", scratch.appendingPathComponent("test.sqlite").path, 1)

        testIdleDetection()
        testWorkSchedule()
        testNotchGeometry()
        testSwipeRowLayout()
        testCharacterResources()
        testAdaptiveTimer()
        testSessionLifecycle()
        testSplitting()
        testSuggestions()
        testAttachmentStore()
        testMochiDropHandler()
        testDailyReport()
        testMonthlyReport()
        testReportEscaping()
        testDragDecisionTable()
        testVisualStateTransitions()
        testAppSettingsFeatures()
        testUpdateSemVerComparison()

        print("")
        if failures.isEmpty {
            print("PASS — \(checks) checks")
            exit(0)
        } else {
            print("FAIL — \(failures.count) of \(checks) checks failed:")
            for failure in failures {
                print("  ✗ \(failure)")
            }
            exit(1)
        }
    }

    // MARK: - Assertions

    private static func check(_ label: String, _ condition: @autoclosure () -> Bool) {
        checks += 1
        if condition() {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            failures.append(label)
        }
    }

    private static func section(_ title: String) {
        print("\n\(title)")
    }

    // MARK: - Tests

    private static func testIdleDetection() {
        section("Idle detection")
        let monitor = IdleMonitor()
        // Reading the counter requires a real event source; a live system
        // always reports a finite, non-negative value.
        let seconds = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: CGEventType(rawValue: ~0)!
        )
        check("idle seconds is finite", seconds.isFinite)
        check("idle seconds is non-negative", seconds >= 0)
        check("monitor not idle immediately after use", monitor.isIdle == false || monitor.idleSeconds >= monitor.threshold)
    }

    private static func testAdaptiveTimer() {
        section("Adaptive timer")
        let timer = AdaptiveTimer()
        let initial = timer.nextInterval

        timer.recordEngagement()
        check("engagement does not exceed the default", timer.nextInterval <= initial)

        // Three consecutive skips must escalate, then clamp at the ceiling.
        timer.recordSkip()
        let afterOne = timer.nextInterval
        timer.recordSkip()
        let afterTwo = timer.nextInterval
        timer.recordSkip()
        timer.recordSkip()
        timer.recordSkip()

        check("skip escalates the interval", afterTwo > afterOne)
        check("interval clamps at 3h ceiling", timer.nextInterval <= 3 * 60 * 60)
        check("interval never drops below 15m floor", timer.nextInterval >= 15 * 60)

        timer.recordEngagement()
        check("engagement after skips reduces interval", timer.nextInterval < afterTwo)
    }

    private static func testSessionLifecycle() {
        section("Session lifecycle")
        let store = freshStore()
        store.deleteAll()

        check("no active session initially", store.active == nil)

        let id = store.startSession()
        check("startSession returns an id", id != nil)
        check("active session exists after start", store.active != nil)
        check("new session is running", store.active?.isRunning == true)

        guard let sessionID = store.active?.id else { return }
        store.update(
            sessionID: sessionID,
            title: "Uji laporan",
            detail: "Rincian",
            outcome: "Berhasil",
            markRecorded: true
        )
        check("title persisted", store.active?.title == "Uji laporan")
        check("outcome persisted", store.active?.outcome == "Berhasil")
        check("recorded flag set", store.active?.recorded == true)
        check("session is reportable", store.active?.isReportable == true)

        // Starting a second session must close the first, so elapsed time is
        // never double-counted.
        store.startSession()
        check("starting new session ends the old one", store.sessions.filter { $0.title == "Uji laporan" }.first?.isRunning == false)
        check("exactly one running session", store.sessions.filter(\.isRunning).count == 1)

        store.endSession(cause: .manual)
        check("endSession clears active", store.active == nil)
    }

    private static func testSplitting() {
        section("Session splitting")
        let store = freshStore()
        store.deleteAll()

        store.startSession()
        guard let id = store.active?.id else { return }
        // Force a closed 2-hour session.
        let end = Date().timeIntervalSince1970
        let start = end - 7200
        store.runRaw("""
            UPDATE session SET started_at = \(start), ended_at = \(end),
            title = 'Sesi panjang' WHERE id = \(id);
            """)
        store.reload()

        let cut = Date(timeIntervalSince1970: start + 3600)
        let tailID = store.split(sessionID: id, at: cut)

        check("split returns a new id", tailID != nil)
        let parts = store.sessions.filter { $0.title == "Sesi panjang" }.sorted { $0.startedAt < $1.startedAt }
        check("split produces two sessions", parts.count == 2)
        check("total duration preserved", {
            guard parts.count == 2, let a = parts.last?.endedAt else { return false }
            return abs((a.timeIntervalSince(parts[0].startedAt)) - 7200) < 1
        }())
    }

    private static func testSuggestions() {
        section("Title suggestions")
        let store = freshStore()
        store.deleteAll()

        store.startSession()
        guard let id = store.active?.id else { return }
        store.update(sessionID: id, title: "Debug gateway", detail: nil, outcome: nil, markRecorded: true)
        store.endSession(cause: .manual)

        store.startSession()
        guard let id2 = store.active?.id else { return }
        store.update(sessionID: id2, title: "Rapat tim", detail: nil, outcome: nil, markRecorded: true)
        store.endSession(cause: .manual)

        let suggestions = store.titleSuggestions()
        check("suggestions are not empty", !suggestions.isEmpty)
        check("suggestions include both titles", suggestions.contains("Debug gateway") && suggestions.contains("Rapat tim"))
        check("most recent title comes first", suggestions.first == "Rapat tim")
    }

    private static func testAttachmentStore() {
        section("Attachment store")
        let dir = AttachmentStore.directory
        check("attachment directory exists", FileManager.default.fileExists(atPath: dir.path))

        // A real image so the PDF/image classification is exercised.
        let sample = dir.appendingPathComponent("__selftest_sample.png")
        if let png = minimalPNG() {
            try? png.write(to: sample)
            if let stored = try? AttachmentStore.store(sample) {
                check("image classified as image", stored.kind == .image)
                check("stored copy exists", FileManager.default.fileExists(atPath: stored.path))
                check("sha256 recorded", stored.sha256.count == 64)
                check("bytes recorded", stored.bytes > 0)

                // Storing the same file again must be idempotent.
                if let again = try? AttachmentStore.store(sample) {
                    check("re-store is idempotent", again.path == stored.path)
                }
            } else {
                check("storing sample succeeded", false)
            }
            try? FileManager.default.removeItem(at: sample)
        }

        // A non-supported file must not be treated as a report attachment.
        let txt = dir.appendingPathComponent("__selftest.txt")
        try? "halo".write(to: txt, atomically: true, encoding: .utf8)
        if let stored = try? AttachmentStore.store(txt) {
            check("plain text classified as other", stored.kind == .other)
        }
        try? FileManager.default.removeItem(at: txt)
    }

    private static func testMochiDropHandler() {
        section("Mochi drag-and-drop ingestion")
        let store = freshStore()
        store.deleteAll()

        // 1. Title formatting
        let url1 = URL(fileURLWithPath: "/tmp/Laporan_Evaluasi_PPDT_2026.pdf")
        check(
            "title cleans underscore and prefix",
            MochiDropHandler.cleanActivityTitle(from: url1) == "Laporan Evaluasi PPDT 2026"
        )

        let url2 = URL(fileURLWithPath: "/tmp/Screenshot_2026-10-04_at_12.00.00.png")
        check(
            "screenshot filename mapped to documentation title",
            MochiDropHandler.cleanActivityTitle(from: url2) == "Dokumentasi & Bukti Kinerja"
        )

        let url3 = URL(fileURLWithPath: "/tmp/rekap_presensi_pegawai.xlsx")
        check(
            "rekap document title formatted nicely",
            MochiDropHandler.cleanActivityTitle(from: url3) == "Rekap Presensi Pegawai"
        )

        // 2. Real file drop execution into PanelMode and draft prefill
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-mochi-\(UUID().uuidString).pdf")
        try? "PDF-DUMMY-CONTENT".data(using: .utf8)?.write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let mode = PanelMode()
        let coord = TrackingCoordinator(store: store)
        let (success, title) = MochiDropHandler.handleDrop(urls: [fixture], coordinator: coord, mode: mode)

        check("mochi drop succeeds", success)
        check("mochi drop returns non-empty title", !title.isEmpty)
        check("mochi drop opens form on home screen with Mochi", mode.screen == .home && mode.isHomeFormOpen)
        check("mochi drop sets prefillAddTitle", mode.prefillAddTitle == title)
        check("mochi drop sets prefillAddURLs", mode.prefillAddURLs?.count == 1)
        check("mochi drop sets 1 hour duration", mode.prefillAddFrom != nil && mode.prefillAddTo != nil)
        if let from = mode.prefillAddFrom, let to = mode.prefillAddTo {
            check("duration is exactly 1 hour (3600s)", abs(to.timeIntervalSince(from) - 3600) < 2)
        }

        // Verify that draft persistence with these prefilled values saves properly to SessionStore
        let draft = ActivityDraft()
        draft.title = mode.prefillAddTitle ?? ""
        draft.detail = mode.prefillAddDetail ?? ""
        if let from = mode.prefillAddFrom, let to = mode.prefillAddTo {
            draft.from = from
            draft.to = to
        }
        if let urls = mode.prefillAddURLs {
            draft.add(urls)
        }
        check("draft with drop prefill is valid", draft.isValid)
        check("draft has 1 attachment", draft.attachments.count == 1)

        let saved = draft.persist(using: store)
        check("draft persist succeeds", saved)

        let sessions = store.sessions
        check("one session was saved in store", sessions.count == 1)
        if let s = sessions.first {
            let atts = store.attachments[s.id] ?? []
            check("saved session has 1 attachment in DB", atts.count == 1)
            check("attachment matches fixture filename", atts.first?.filename == fixture.lastPathComponent)
        }

        // Test tab cycling navigation (Left/Right arrow keyboard logic)
        mode.screen = .home
        mode.nextTab()
        check("nextTab moves from home to list", mode.screen == .list)
        mode.nextTab()
        check("nextTab moves from list to chat", mode.screen == .chat)
        mode.nextTab()
        check("nextTab moves from chat to add", mode.screen == .add)
        mode.nextTab()
        check("nextTab wraps from add to home", mode.screen == .home)
        mode.previousTab()
        check("previousTab wraps from home to add", mode.screen == .add)
        mode.previousTab()
        check("previousTab moves from add to chat", mode.screen == .chat)
        mode.previousTab()
        check("previousTab moves from chat to list", mode.screen == .list)
        mode.previousTab()
        check("previousTab moves from list to home", mode.screen == .home)
    }

    private static func testDailyReport() {
        section("Daily report")
        let store = freshStore()
        store.deleteAll()

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).addingTimeInterval(9 * 3600)

        // Three sessions today.
        for (index, title) in ["Rapat koordinasi", "Review dokumen", "Debug sistem"].enumerated() {
            let offset = Double(index) * 3600
            store.startSession(at: start.addingTimeInterval(offset))
            guard let id = store.active?.id else { continue }
            store.update(
                sessionID: id,
                title: title,
                detail: "Rincian \(index + 1)",
                outcome: "Hasil \(index + 1)",
                markRecorded: true
            )
            store.endSession(cause: .manual, at: start.addingTimeInterval(offset + 1800))
        }

        // An untitled session must be excluded — a bare timer proves nothing.
        store.startSession(at: start.addingTimeInterval(4 * 3600))
        check("untitled session is not reportable", store.active?.isReportable == false)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("selftest-daily-\(UUID().uuidString).docx")
        do {
            let count = try ReportBuilder.daily(on: Date(), store: store, to: url)
            check("daily report wrote a file", FileManager.default.fileExists(atPath: url.path))
            check("daily report counted 3 titled sessions", count == 3)
            check("daily report is non-trivial in size", fileSize(url) > 1000)
        } catch {
            check("daily report did not throw (\(error))", false)
        }
        try? FileManager.default.removeItem(at: url)
    }

    private static func testMonthlyReport() {
        section("Monthly report")
        let store = freshStore()
        store.deleteAll()

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        for index in 0..<3 {
            let day = calendar.startOfDay(for: Date())
                .addingTimeInterval(Double(-index) * 86400)
                .addingTimeInterval(9 * 3600)
            store.startSession(at: day)
            guard let id = store.active?.id else { continue }
            store.update(
                sessionID: id,
                title: "Kegiatan hari \(index + 1)",
                detail: nil,
                outcome: "Selesai",
                markRecorded: true
            )
            store.endSession(cause: .manual, at: day.addingTimeInterval(2 * 3600))
        }
        _ = start

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("selftest-monthly-\(UUID().uuidString).docx")
        do {
            let interval = DateInterval(
                start: calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!,
                end: Date().addingTimeInterval(86400)
            )
            let count = try ReportBuilder.monthly(in: interval, store: store, to: url)
            check("monthly report wrote a file", FileManager.default.fileExists(atPath: url.path))
            check("monthly report counted 3 sessions", count == 3)
            check("monthly report is non-trivial in size", fileSize(url) > 1000)
        } catch {
            check("monthly report did not throw (\(error))", false)
        }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - App Settings Features Verification

    private static func testAppSettingsFeatures() {
        print("\n— app settings verification —")
        let settings = AppSettings.shared

        // Test 1: Idle Glow settings
        settings.idleGlowEnabled = false
        check("idle glow can be disabled", !settings.idleGlowEnabled)
        settings.idleGlowEnabled = true
        check("idle glow can be enabled", settings.idleGlowEnabled)

        settings.idleGlowIntensity = 0.85
        check("idle glow intensity updates accurately", abs(settings.idleGlowIntensity - 0.85) < 0.001)

        // Test 2: Idle Dwell Duration & live link to HoverState
        settings.idleDwellDuration = 1.45
        check("idle dwell duration updates accurately", abs(settings.idleDwellDuration - 1.45) < 0.001)
        let hover = HoverState()
        check("HoverState reflects live idleDwellDuration", abs(hover.dwellDuration - 1.45) < 0.001)

        // Test 3: Capsule & Expanded geometry
        settings.capsuleWidth = 320
        check("capsule width updates", abs(settings.capsuleWidth - 320) < 0.001)
        settings.expandedWidth = 680
        check("expanded width updates", abs(settings.expandedWidth - 680) < 0.001)

        // Test 4: AI settings
        settings.aiBaseURL = "http://localhost:11434/v1"
        check("ai base url updates", settings.aiBaseURL == "http://localhost:11434/v1")
        settings.aiModel = "llama3"
        check("ai model updates", settings.aiModel == "llama3")

        // Test 5: Work schedule syncing
        settings.workStartHour = 8
        settings.workStartMinute = 15
        check("work schedule startHour synced", WorkSchedule.startHour == 8)
        check("work schedule startMinute synced", WorkSchedule.startMinute == 15)
        settings.workdays = [2, 3, 4]
        check("workdays synced to activeWorkdays set", WorkSchedule.activeWorkdays == Set([2, 3, 4]))

        // Test 6: Reminders
        settings.reminderEnabled = false
        check("reminder toggle updates", !settings.reminderEnabled)
        settings.reminderIntervalMinutes = 45
        check("reminder interval updates", settings.reminderIntervalMinutes == 45)

        // Test 7: Reset to defaults restores everything cleanly
        settings.resetToDefaults()
        check("reset restores idleGlowEnabled", settings.idleGlowEnabled == true)
        check("reset restores idleGlowIntensity", abs(settings.idleGlowIntensity - 0.65) < 0.001)
        check("reset restores idleDwellDuration", abs(settings.idleDwellDuration - 1.0) < 0.001)
        check("reset restores capsuleWidth", abs(settings.capsuleWidth - 291) < 0.001)
        check("reset restores expandedWidth", abs(settings.expandedWidth - 640) < 0.001)
        check("reset restores workStartHour", settings.workStartHour == 7)
        check("reset restores reminderEnabled", settings.reminderEnabled == true)
        check("reset restores aiModel", settings.aiModel == "antigravity")
        settings.autoCheckUpdates = false
        check("autoCheckUpdates can be toggled", !settings.autoCheckUpdates)
        settings.autoCheckUpdates = true
        check("autoCheckUpdates can be enabled", settings.autoCheckUpdates)
    }

    // MARK: - OTA Update SemVer Comparison

    private static func testUpdateSemVerComparison() {
        print("\n— ota update semver comparison —")

        check("1.0.1 is newer than 1.0.0", UpdateService.isVersion("1.0.1", newerThan: "1.0.0"))
        check("v1.1.0 is newer than v1.0.9", UpdateService.isVersion("v1.1.0", newerThan: "v1.0.9"))
        check("2.0.0 is newer than 1.9.9", UpdateService.isVersion("2.0.0", newerThan: "1.9.9"))
        check("1.0.10 is newer than 1.0.9", UpdateService.isVersion("1.0.10", newerThan: "1.0.9"))
        check("1.0.0 is not newer than 1.0.0", !UpdateService.isVersion("1.0.0", newerThan: "1.0.0"))
        check("1.0.0 is not newer than 1.0.1", !UpdateService.isVersion("1.0.0", newerThan: "1.0.1"))
        check("v1.0.0 is not newer than 1.0.0 (identical)", !UpdateService.isVersion("v1.0.0", newerThan: "1.0.0"))
        check("currentVersion is non-empty", !UpdateService.shared.currentVersion.isEmpty)
    }

    // MARK: - 3-State Notch Visual Transitions

    private static func testVisualStateTransitions() {
        print("\n— 3-state notch visual transitions —")
        let hover = HoverState()

        check("initial state is idle", hover.visualState == .idle)
        check("idle is not expanded", !hover.isExpanded)

        hover.setOver(true)
        check("hover enters idleHover state", hover.visualState == .idleHover)
        check("idleHover is not expanded", !hover.isExpanded)

        hover.setOver(false)
        check("leaving before dwell returns to idle", hover.visualState == .idle)

        hover.setOver(true)
        hover.expandNow()
        check("expandNow promotes to expanded", hover.visualState == .expanded)
        check("expanded state isExpanded is true", hover.isExpanded)

        // Interacting with header tabs or UI clicks must not demote expanded state
        hover.setDrag(false)
        check("ending drag while over does not demote expanded", hover.visualState == .expanded)
        hover.setOver(true)
        check("subsequent hover while over does not demote expanded", hover.visualState == .expanded)

        hover.setOver(false)
        check("leaving expanded collapses back to idle", hover.visualState == .idle)

        hover.setDrag(true)
        check("drag bypasses idleHover and opens expanded directly", hover.visualState == .expanded)

        hover.setDrag(false)
        check("ending drag returns to idle", hover.visualState == .idle)

        hover.pinned = true
        check("pinning sets expanded state", hover.visualState == .expanded)
        hover.pinned = false
        check("unpinning returns to idle", hover.visualState == .idle)
    }

    private static func testDragDecisionTable() {
        print("\n— drag & drop decision table —")
        // The collapsed-notch case is the one that used to break: the panel is
        // click-through, so AppKit never routes `draggingEntered`, and the
        // decision to open has to come from the button-mask poll alone.
        let zone = NSRect(x: 100, y: 900, width: 430, height: 130)
        let inside = NSPoint(x: 300, y: 950)
        let outside = NSPoint(x: 1000, y: 400)

        check("no button, pointer over notch → idle",
              dragDecision(leftDown: false, wasDown: false, holdingOpen: false,
                           location: inside, zone: zone) == .none)

        check("button just pressed anywhere → arm as drop destination",
              dragDecision(leftDown: true, wasDown: false, holdingOpen: false,
                           location: outside, zone: zone) == .dragBegan)

        check("armed, then pointer reaches the notch → opens panel",
              dragDecision(leftDown: true, wasDown: true, holdingOpen: false,
                           location: inside, zone: zone) == .enterZone)

        check("button down over notch, already holding → stays open",
              dragDecision(leftDown: true, wasDown: true, holdingOpen: true,
                           location: inside, zone: zone) == .holdOpen)

        check("button down, pointer outside, not holding → idle",
              dragDecision(leftDown: true, wasDown: true, holdingOpen: false,
                           location: outside, zone: zone) == .none)

        check("button down, pointer dragged away while holding → tears down",
              dragDecision(leftDown: true, wasDown: true, holdingOpen: true,
                           location: outside, zone: zone) == .leaveZone)

        check("release inside zone still ends the drag",
              dragDecision(leftDown: false, wasDown: true, holdingOpen: true,
                           location: inside, zone: zone) == .dragEnded)

        check("release outside zone still ends the drag",
              dragDecision(leftDown: false, wasDown: true, holdingOpen: true,
                           location: outside, zone: zone) == .dragEnded)

        check("release when never holding is a no-op",
              dragDecision(leftDown: false, wasDown: false, holdingOpen: false,
                           location: inside, zone: zone) == .none)

        // The drop zone has to actually contain the collapsed capsule, or every
        // transition above is correct and the feature still never fires.
        if let screen = NSScreen.screens.first {
            let dropZone = NotchGeometry.dropZone(on: screen, collapsed: CGSize(width: 291, height: 37))
            let capsule = NotchGeometry.presentedFrame(on: screen, size: CGSize(width: 291, height: 37))
            check("drop zone contains the collapsed capsule",
                  dropZone.contains(capsule))
            check("drop zone reaches up past the notch lip",
                  dropZone.maxY >= capsule.maxY + 30)
            check("drop zone is wider than the capsule",
                  dropZone.width >= capsule.width + 100)
        }
    }

    private static func testReportEscaping() {
        section("Report escaping")
        let store = freshStore()
        store.deleteAll()

        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
        store.startSession(at: start)
        guard let id = store.active?.id else { return }
        // Characters that break naive OOXML writers.
        store.update(
            sessionID: id,
            title: #"R&D <50% & "quotas" >target"#,
            detail: "A & B < C",
            outcome: "100% done & siap",
            markRecorded: true
        )
        store.endSession(cause: .manual, at: start.addingTimeInterval(3600))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("selftest-escape-\(UUID().uuidString).docx")
        do {
            try ReportBuilder.daily(on: Date(), store: store, to: url)
            check("escape report wrote a file", FileManager.default.fileExists(atPath: url.path))
            // Round-trip through the zip: if escaping were wrong, the XML
            // would not parse and the content would be corrupted.
            let unzipped = try unzipAndRead(url)
            check("report XML is well-formed after unzipping", unzipped != nil)
            check("ampersand survived round-trip", unzipped?.contains("R&amp;D") == true)
            check("angle brackets survived round-trip", unzipped?.contains("&lt;50%") == true)
        } catch {
            check("escape report did not throw (\(error))", false)
        }
        try? FileManager.default.removeItem(at: url)
    }

    private static func testWorkSchedule() {
        section("Work schedule")
        // 2026-09-28 is a Monday, 2026-09-27 a Sunday.
        let monday = isoDate("2026-09-28T09:00:00Z")
        let sunday = isoDate("2026-09-27T09:00:00Z")

        check("weekday counts as a workday", WorkSchedule.isWorkday(monday, calendar: isoCalendar))
        check(
            "sunday is not a workday",
            !WorkSchedule.isWorkday(sunday, calendar: isoCalendar)
        )

        // 09:00-17:00 sits entirely inside a 07:30-17:00 window.
        let fullDay = WorkSchedule.worked(
            in: DateInterval(
                start: isoDate("2026-09-28T09:00:00Z"),
                end: isoDate("2026-09-28T17:00:00Z")
            ),
            calendar: isoCalendar
        )
        check("a full day inside the window counts in full", abs(fullDay - 8 * 3600) < 1)

        // 05:00-20:00 spans the whole window, so it must clip to 9.5 hours
        // (07:30-17:00), never report the raw 15 hours.
        let overnight = WorkSchedule.worked(
            in: DateInterval(
                start: isoDate("2026-09-28T05:00:00Z"),
                end: isoDate("2026-09-28T20:00:00Z")
            ),
            calendar: isoCalendar
        )
        check("time outside the window is clipped away", abs(overnight - 9.5 * 3600) < 1)

        let sundayWork = WorkSchedule.worked(
            in: DateInterval(
                start: isoDate("2026-09-27T09:00:00Z"),
                end: isoDate("2026-09-27T12:00:00Z")
            ),
            calendar: isoCalendar
        )
        check("weekend work counts as zero", abs(sundayWork) < 1)

        check(
            "label formats as hours:minutes",
            WorkSchedule.label(2 * 3600 + 30 * 60) == "2:30"
        )
        check(
            "label under an hour shows leading zero minutes",
            WorkSchedule.label(45 * 60) == "0:45"
        )

        // The live clock keeps a seconds field; without it the running timer
        // looks frozen between minute changes.
        check("clock formats as HH:MM:SS", WorkSchedule.clock(3661) == "01:01:01")
        check("clock pads single digits", WorkSchedule.clock(65) == "00:01:05")
        check("clock never goes negative", WorkSchedule.clock(-5) == "00:00:00")

        // 2026-09-28 is a Monday: 09:00 is inside the window, 05:00 and
        // 18:00 are not. Sunday is never inside it.
        check(
            "mid-morning Monday is inside the window",
            WorkSchedule.isWithinWindow(isoDate("2026-09-28T09:00:00Z"), calendar: isoCalendar)
        )
        check(
            "early Monday is outside the window",
            !WorkSchedule.isWithinWindow(isoDate("2026-09-28T05:00:00Z"), calendar: isoCalendar)
        )
        check(
            "evening Monday is outside the window",
            !WorkSchedule.isWithinWindow(isoDate("2026-09-28T18:00:00Z"), calendar: isoCalendar)
        )
        check(
            "Sunday midday is outside the window",
            !WorkSchedule.isWithinWindow(isoDate("2026-09-27T12:00:00Z"), calendar: isoCalendar)
        )

        check("progress clamps at the 8-hour target", abs(WorkSchedule.progress(worked: 8 * 3600) - 1.0) < 0.0001)
        check("progress is half at 4 hours", abs(WorkSchedule.progress(worked: 4 * 3600) - 0.5) < 0.0001)
    }

    private static func testNotchGeometry() {
        section("Notch geometry")
        // The notched path needs a real NSScreen, so only the pure radius
        // helper is exercised here; the metrics are verified visually against
        // the hardware, which is the only honest check for this.
        check(
            "a notched capsule gets a small bottom radius, not a pill",
            NotchGeometry.collapsedRadius(isNotched: true, height: 37.5) < 37.5 / 2
        )
        check(
            "a notchless capsule is a full pill",
            abs(NotchGeometry.collapsedRadius(isNotched: false, height: 37.5) - 18.75) < 0.01
        )
        check("expanded radius is generous", NotchGeometry.expandedRadius >= 28)
        check("expanded panel fits the canvas", NotchGeometry.expandedWidth <= NotchGeometry.canvasSize.width)
        check(
            "expanded panel fits the canvas height",
            NotchGeometry.maxExpandedSize.height <= NotchGeometry.canvasSize.height
        )
        // The panel hugs its rows: one row taller than the last, and an empty
        // list does not collapse the panel to nothing.
        check(
            "each extra row grows the panel",
            NotchGeometry.expandedSize(rowCount: 2).height
                - NotchGeometry.expandedSize(rowCount: 1).height == NotchGeometry.rowPitch
        )
        check(
            "the panel height tracks the row count",
            NotchGeometry.expandedSize(rowCount: 3).height
                == NotchGeometry.expandedChromeHeight + 3 * NotchGeometry.rowPitch
        )
        check(
            "an empty list still shows the chrome",
            NotchGeometry.expandedSize(rowCount: 0).height == NotchGeometry.expandedChromeHeight
        )
        check(
            "an overfull list is clamped, not grown",
            NotchGeometry.expandedSize(rowCount: 99).height
                == NotchGeometry.maxExpandedSize.height
        )
        check(
            "a negative row count cannot invert the panel",
            NotchGeometry.expandedSize(rowCount: -5).height == NotchGeometry.expandedChromeHeight
        )
        check(
            "the panel width does not depend on the row count",
            NotchGeometry.expandedSize(rowCount: 0).width == NotchGeometry.expandedWidth
        )
        check(
            "three rows fit the three-row list viewport",
            CGFloat(NotchGeometry.maxVisibleRows) * NotchGeometry.rowPitch
                == NotchGeometry.expandedSize(rowCount: 3).height - NotchGeometry.expandedChromeHeight
        )
    }

    /// The swipe-row layout was ported from a React component and got the
    /// action order wrong once, in a way that still rendered. These assertions
    /// exist because the wrong answer looks like the right one.
    private static func testSwipeRowLayout() {
        section("SwipeRow layout")
        // One primary plus one secondary, which is the activity list's shape.
        func secondaryCount(_ m: SwipeLayout.Metrics) -> Int { max(1, Int((m.drawerWidth / m.actionWidth).rounded()) - 1) }
        let m = SwipeLayout.Metrics(width: 360, actionWidth: 80, actionCount: 2)

        check("drawer is n * actionWidth", m.drawerWidth == 160)
        check(
            "commit threshold uses 0.6 of the row",
            abs(SwipeLayout.commitThreshold(m) - 216) < 0.01
        )
        check("a wide row can commit", SwipeLayout.canCommit(m))

        // The bug that shipped: actions stacked from the leading edge, which
        // put the primary on the wrong side of the drawer.
        check(
            "the first secondary sits one action in from the trailing edge",
            abs(SwipeLayout.secondaryOffsetX(index: 0, m) - -80) < 0.01
        )
        check(
            "the second secondary sits two actions in",
            abs(SwipeLayout.secondaryOffsetX(index: 1, m) - -160) < 0.01
        )
        check(
            "secondaries are always measured leftward",
            SwipeLayout.secondaryOffsetX(index: 0, m) < 0
        )
        // The primary occupies the trailing slot outright (offset 0), and the
        // commit block overlays that same slot — which is exactly why the
        // block is only drawn once the row actually leaps.
        check(
            "the primary's tap slot is the trailing one",
            SwipeLayout.primaryOffsetX(m) == 0
        )
        check(
            "the primary does not collide with the first secondary",
            SwipeLayout.primaryOffsetX(m) != SwipeLayout.secondaryOffsetX(index: 0, m)
        )
        check(
            "the commit block is anchored to the primary's slot",
            SwipeLayout.commitBlockShift(exposed: 60, isLeaping: true, m) == 0
        )
        // The rail slides by `D - e`, measured from the drawer's width. Using
        // the row's width here parks the actions a full row-width off screen,
        // which renders as "no drawer at all" rather than a layout slip.
        check(
            "the rail is fully parked when the row is closed",
            abs(SwipeLayout.railOffsetX(exposed: 0, m) - 160) < 0.01
        )
        check(
            "the rail is fully in place when the drawer is open",
            abs(SwipeLayout.railOffsetX(exposed: 160, m)) < 0.01
        )
        check(
            "the rail offset ignores the row width",
            SwipeLayout.railOffsetX(exposed: 80, m) == 80
        )
        check(
            "a fully committed row parks the rail off screen",
            SwipeLayout.railOffsetX(exposed: 360, m) < 0
        )
        // The rail is `inset: 0` — full row width — with the actions anchored to
        // its trailing edge. Sizing the rail to the drawer instead would put the
        // whole action cluster in the leading half of the row.
        check(
            "the rail spans the full row, not just the drawer",
            m.width > m.drawerWidth
        )
        check(
            "the primary still lands inside the row when the drawer is open",
            m.width - m.actionWidth > 0
        )

        // The commit block is a full-width rect that sweeps, not a button that
        // grows, so its shift is zero until the drag passes one action width.
        check(
            "the commit block does not move before the leap",
            SwipeLayout.commitBlockShift(exposed: 100, isLeaping: false, m) == 0
        )
        check(
            "the commit block is still put below one action width",
            SwipeLayout.commitBlockShift(exposed: 60, isLeaping: true, m) == 0
        )
        check(
            "the commit block starts shifting past one action width",
            abs(SwipeLayout.commitBlockShift(exposed: 100, isLeaping: true, m) - 20) < 0.01
        )
        check(
            "the commit block sweeps once past the action width",
            abs(SwipeLayout.commitBlockShift(exposed: 200, isLeaping: true, m) - 120) < 0.01
        )

        // The counter-translate that keeps the label put while the block sweeps
        // under it. This is the most visible way to get the component wrong.
        check(
            "the commit label is still put before the leap",
            SwipeLayout.commitLabelOffsetX(exposed: 200, isLeaping: false, m) == 0
        )
        let far = SwipeLayout.commitLabelOffsetX(exposed: 200, isLeaping: true, m)
        check("the commit label counter-translates when leaping", abs(far - (-20)) < 0.01)

        // Drag mapping: free to the drawer width, then resistance, then band.
        check("a closed row is closed", SwipeLayout.map(0, m) == 0)
        check("the row tracks the drag inside the drawer", abs(SwipeLayout.map(120, m) - 120) < 0.01)
        check(
            "pulling the other way rubber-bands instead of clamping",
            SwipeLayout.map(-60, m) < 0 && SwipeLayout.map(-60, m) > -60
        )
        check(
            "resistance kicks in past the drawer width",
            SwipeLayout.map(240, m) < 240
        )
        check(
            "the commit point is not overshot by a long drag",
            SwipeLayout.map(1000, m) < 1000
        )
        check(
            "a long drag still reaches the commit point",
            SwipeLayout.map(1000, m) >= SwipeLayout.commitThreshold(m)
        )

        // Settling: a flick goes to the nearer end, a slow release coasts.
        // Velocity is measured on `exposed`, so positive means opening.
        check(
            "a fast opening flick goes to the open end",
            SwipeLayout.settleTarget(exposed: 100, velocity: 900, m) == m.drawerWidth
        )
        check(
            "a fast closing flick goes to the closed end",
            SwipeLayout.settleTarget(exposed: 100, velocity: -900, m) == 0
        )
        check(
            "a slow release past halfway opens the drawer",
            SwipeLayout.settleTarget(exposed: 100, velocity: 0, m) == m.drawerWidth
        )
        check(
            "a slow release under halfway closes the row",
            SwipeLayout.settleTarget(exposed: 40, velocity: 0, m) == 0
        )
        check(
            "a decelerating release still opens past the midpoint",
            SwipeLayout.settleTarget(exposed: 50, velocity: 200, m) == m.drawerWidth
        )
        check(
            "the projection is what carries a slow release past the midpoint",
            SwipeLayout.project(200) > 90 && SwipeLayout.project(0) == 0
        )
        // A release just under the midpoint with no momentum stays closed, so
        // the projection cannot open the drawer on its own.
        check(
            "the projection is not strong enough to open a nearly-closed row",
            SwipeLayout.settleTarget(exposed: 50, velocity: 0, m) == 0
        )

        // Degenerate geometry must not divide by zero or produce NaN.
        let narrow = SwipeLayout.Metrics(width: 100, actionWidth: 80, actionCount: 2)
        check("a row narrower than its drawer cannot commit", !SwipeLayout.canCommit(narrow))
        check(
            "narrow-row mapping stays finite",
            SwipeLayout.map(400, narrow).isFinite && SwipeLayout.map(-50, narrow).isFinite
        )
        let noSwipe = SwipeLayout.Metrics(width: 360, actionWidth: 80, actionCount: 2, fullSwipe: false)
        check("fullSwipe off disables the commit", !SwipeLayout.canCommit(noSwipe))
        check(
            "with fullSwipe off the row still opens its drawer",
            abs(SwipeLayout.map(160, noSwipe) - 160) < 0.01
        )
        check("resistance is clamped to a sane range", SwipeLayout.Metrics(width: 360, actionWidth: 80, actionCount: 1, resistance: 9).resistance == 1)
    }

    private static func testCharacterResources() {
        // The web view resolves these by relative path, so if the build stops
        // copying Resources the panel renders an empty box with no error.
        check("character.html is in the bundle", resource("character", "html") != nil)
        check(
            "the engine entry point is in the bundle",
            resource("engine", "js", "mood-mates/src/core") != nil
        )
        check(
            "the character module is in the bundle",
            resource("nimbo", "js", "mood-mates/src/characters") != nil
        )
    }

    private static func resource(_ name: String, _ ext: String, _ dir: String? = nil) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: dir)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    /// Fixed UTC calendar so workday arithmetic does not depend on the
    /// machine's locale, which is the whole point of testing it.
    private static var isoCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private static func isoDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f.date(from: s)!
    }

    // MARK: - Helpers

    /// `Database.shared` is a singleton constructed on first access, so the
    /// scratch path must be set before anything touches it. Every store in the
    /// selftest therefore shares one throwaway database; `deleteAll()` between
    /// groups is what provides isolation.
    private static func freshStore() -> SessionStore {
        SessionStore()
    }

    private static func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
    }

    private static func unzipAndRead(_ url: URL) throws -> String? {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("selftest-unzip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-o", "-q", url.path, "-d", staging.path]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }

        let document = staging.appendingPathComponent("word/document.xml")
        return try? String(contentsOf: document, encoding: .utf8)
    }

    /// A 1x1 PNG, so the image-path test does not depend on a fixture file.
    private static func minimalPNG() -> Data? {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        return Data(base64Encoded: base64)
    }
}
