import SwiftUI
import Combine

/// User-tunable settings, persisted in `UserDefaults`.
///
/// Every value has a default that matches the geometry the app shipped with, so
/// a fresh install — or a corrupted defaults plist — falls back to sane
/// numbers instead of a zero-sized panel.
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let capsuleWidth = "settings.capsuleWidth"
        static let capsuleHeight = "settings.capsuleHeight"
        static let expandedWidth = "settings.expandedWidth"
        static let expandedHeight = "settings.expandedHeight"
        static let hoverOpenDelay = "settings.hoverOpenDelay"
        static let hoverCloseDelay = "settings.hoverCloseDelay"
        static let storageFolderBookmark = "settings.storageFolderBookmark"
        static let rowStagger = "settings.rowStagger"
        static let workStartHour = "settings.workStartHour"
        static let workStartMinute = "settings.workStartMinute"
        static let workEndHour = "settings.workEndHour"
        static let workEndMinute = "settings.workEndMinute"
        static let workdays = "settings.workdays"
        static let reminderEnabled = "settings.reminderEnabled"
        static let reminderIntervalMinutes = "settings.reminderIntervalMinutes"
        static let reminderSoundEnabled = "settings.reminderSoundEnabled"
        static let aiBaseURL = "settings.aiBaseURL"
        static let aiApiKey = "settings.aiApiKey"
        static let aiModel = "settings.aiModel"
    }

    private let defaults: UserDefaults

    /// Singleton instance for background & tracking coordination.
    static let shared = AppSettings()

    // MARK: - Geometry

    /// Idle capsule width in points. The shipped value is 20% wider than the
    /// hardware notch on each side; anything from 220 to 420 still reads as
    /// "attached to the notch" rather than a floating rectangle.
    @Published var capsuleWidth: Double {
        didSet { defaults.set(capsuleWidth, forKey: Key.capsuleWidth) }
    }

    /// Idle capsule height in points. Matches hardware notch height (37.5 pt on M4/M3/M2/M1)
    /// but tunable in points (28 to 56 pt).
    @Published var capsuleHeight: Double {
        didSet { defaults.set(capsuleHeight, forKey: Key.capsuleHeight) }
    }

    /// Expanded panel width in points.
    @Published var expandedWidth: Double {
        didSet { defaults.set(expandedWidth, forKey: Key.expandedWidth) }
    }

    /// Expanded panel height in points. This is the *chrome* budget; the
    /// activity list gets whatever is left over, so lowering this below the
    /// header + button height would starve the list.
    @Published var expandedHeight: Double {
        didSet { defaults.set(expandedHeight, forKey: Key.expandedHeight) }
    }

    // MARK: - Hover

    /// How long the pointer must rest inside the capsule before the panel
    /// opens. Zero opens on the first pixel of hover, which is jarring at the
    /// notch edge; 120ms is the sweet spot where a brush-past does not open it.
    @Published var hoverOpenDelay: Double {
        didSet { defaults.set(hoverOpenDelay, forKey: Key.hoverOpenDelay) }
    }

    /// Grace period before the panel closes after the pointer leaves. Without
    /// it, reaching for the list scrolls the pointer across the gap between the
    /// capsule and the panel, and the panel snaps shut mid-reach.
    @Published var hoverCloseDelay: Double {
        didSet { defaults.set(hoverCloseDelay, forKey: Key.hoverCloseDelay) }
    }

    /// Seconds between consecutive rows in the list entrance cascade. Zero
    /// makes the list arrive as a single block, which is the snap this
    /// animation replaced; past ~0.12 the rows read as a slow trickle rather
    /// than as one gesture.
    @Published var rowStagger: Double {
        didSet { defaults.set(rowStagger, forKey: Key.rowStagger) }
    }

    // MARK: - Work Schedule

    /// Work start hour (0...23, default 7 for 07:xx).
    @Published var workStartHour: Int {
        didSet {
            defaults.set(workStartHour, forKey: Key.workStartHour)
            syncWorkSchedule()
        }
    }

    /// Work start minute (0...59, default 30 for xx:30).
    @Published var workStartMinute: Int {
        didSet {
            defaults.set(workStartMinute, forKey: Key.workStartMinute)
            syncWorkSchedule()
        }
    }

    /// Work end hour (0...23, default 17 for 17:xx).
    @Published var workEndHour: Int {
        didSet {
            defaults.set(workEndHour, forKey: Key.workEndHour)
            syncWorkSchedule()
        }
    }

    /// Work end minute (0...59, default 0 for xx:00).
    @Published var workEndMinute: Int {
        didSet {
            defaults.set(workEndMinute, forKey: Key.workEndMinute)
            syncWorkSchedule()
        }
    }

    /// Active workdays as Calendar weekdays: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat.
    /// Default [2, 3, 4, 5, 6] (Mon–Fri).
    @Published var workdays: [Int] {
        didSet {
            defaults.set(workdays, forKey: Key.workdays)
            syncWorkSchedule()
        }
    }

    // MARK: - Reminders

    /// Whether checkpoint reminder prompts are active.
    @Published var reminderEnabled: Bool {
        didSet { defaults.set(reminderEnabled, forKey: Key.reminderEnabled) }
    }

    /// Interval in minutes between checkpoint reminders (15...180, default 60).
    @Published var reminderIntervalMinutes: Int {
        didSet { defaults.set(reminderIntervalMinutes, forKey: Key.reminderIntervalMinutes) }
    }

    /// Whether to play a gentle chime when a reminder fires.
    @Published var reminderSoundEnabled: Bool {
        didSet { defaults.set(reminderSoundEnabled, forKey: Key.reminderSoundEnabled) }
    }

    func syncWorkSchedule() {
        WorkSchedule.startHour = workStartHour
        WorkSchedule.startMinute = workStartMinute
        WorkSchedule.endHour = workEndHour
        WorkSchedule.endMinute = workEndMinute
        WorkSchedule.activeWorkdays = Set(workdays)
    }

    // MARK: - Storage

    /// Security-scoped bookmark to the folder attachments and exports are
    /// written to. Stored as a bookmark rather than a plain path so the app
    /// keeps access when the folder is on a volume that requires it.
    @Published var storageFolderBookmark: Data? {
        didSet { defaults.set(storageFolderBookmark, forKey: Key.storageFolderBookmark) }
    }

    /// The resolved folder, or `nil` when nothing has been granted yet. Resolving
    /// a stale bookmark returns `nil` rather than throwing, so a folder deleted
    /// since the last launch degrades to "ask again" instead of crashing.
    var storageFolderURL: URL? {
        guard let data = storageFolderBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return url
    }

    /// Replace the storage folder with a newly picked one. Returns false when
    /// the pick was cancelled, so the caller can leave the UI untouched.
    @discardableResult
    func setStorageFolder(_ url: URL) -> Bool {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            storageFolderBookmark = data
            return true
        } catch {
            return false
        }
    }

    /// Reclaim access to the resolved folder. Must be balanced by
    /// `startAccessingStorageFolder` around any actual file I/O.
    func startAccessingStorageFolder() -> Bool {
        guard let url = storageFolderURL else { return false }
        return url.startAccessingSecurityScopedResource()
    }

    func stopAccessingStorageFolder() {
        storageFolderURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - AI / OpenAI Compatible

    @Published var aiBaseURL: String {
        didSet { defaults.set(aiBaseURL, forKey: Key.aiBaseURL) }
    }

    @Published var aiApiKey: String {
        didSet { defaults.set(aiApiKey, forKey: Key.aiApiKey) }
    }

    @Published var aiModel: String {
        didSet { defaults.set(aiModel, forKey: Key.aiModel) }
    }

    // MARK: - Defaults

    init(
        defaults: UserDefaults = .standard,
        capsuleWidth: Double = 291,
        capsuleHeight: Double = 37.5,
        expandedWidth: Double = 640,
        expandedHeight: Double = 335,
        hoverOpenDelay: Double = 0.08,
        hoverCloseDelay: Double = 0.28,
        storageFolderBookmark: Data? = nil,
        rowStagger: Double = 0.05
    ) {
        self.defaults = defaults
        self.capsuleWidth = Self.read(
            defaults, Key.capsuleWidth, capsuleWidth, range: 220...420)
        self.capsuleHeight = Self.read(
            defaults, Key.capsuleHeight, capsuleHeight, range: 28...56)
        self.expandedWidth = Self.read(
            defaults, Key.expandedWidth, expandedWidth, range: 360...720)
        self.expandedHeight = Self.read(
            defaults, Key.expandedHeight, expandedHeight, range: 260...620)
        self.hoverOpenDelay = Self.read(
            defaults, Key.hoverOpenDelay, hoverOpenDelay, range: 0...1.0)
        self.hoverCloseDelay = Self.read(
            defaults, Key.hoverCloseDelay, hoverCloseDelay, range: 0...2.0)
        self.storageFolderBookmark = defaults.data(forKey: Key.storageFolderBookmark)
            ?? storageFolderBookmark
        self.rowStagger = Self.read(
            defaults, Key.rowStagger, rowStagger, range: 0...0.2)
        self.workStartHour = Self.readInt(defaults, Key.workStartHour, 7, range: 0...23)
        self.workStartMinute = Self.readInt(defaults, Key.workStartMinute, 30, range: 0...59)
        self.workEndHour = Self.readInt(defaults, Key.workEndHour, 17, range: 0...23)
        self.workEndMinute = Self.readInt(defaults, Key.workEndMinute, 0, range: 0...59)
        if let storedDays = defaults.array(forKey: Key.workdays) as? [Int], !storedDays.isEmpty {
            self.workdays = storedDays
        } else {
            self.workdays = [2, 3, 4, 5, 6]
        }
        self.reminderEnabled = defaults.object(forKey: Key.reminderEnabled) as? Bool ?? true
        self.reminderIntervalMinutes = Self.readInt(defaults, Key.reminderIntervalMinutes, 60, range: 15...180)
        self.reminderSoundEnabled = defaults.object(forKey: Key.reminderSoundEnabled) as? Bool ?? true

        self.aiBaseURL = defaults.string(forKey: Key.aiBaseURL) ?? "http://localhost:20128/v1"
        self.aiModel = defaults.string(forKey: Key.aiModel) ?? "antigravity"
        // No baked-in gateway secret: an old hardcoded literal went stale and made
        // every chat return invalid_api_key. AIKeyResolver reads the live 9router
        // key at request time instead.
        let fallbackKey = AIKeyResolver.liveGatewayKey() ?? ""
        self.aiApiKey = defaults.string(forKey: Key.aiApiKey) ?? fallbackKey

        syncWorkSchedule()
    }

    private static func readInt(
        _ defaults: UserDefaults,
        _ key: String,
        _ fallback: Int,
        range: ClosedRange<Int>
    ) -> Int {
        guard let stored = defaults.object(forKey: key) as? Int,
              range.contains(stored)
        else { return fallback }
        return stored
    }

    /// Read a stored double, falling back when the key is absent, unparseable,
    /// or outside the range the UI can represent — a plist edited by hand or
    /// left over from an older build should not be able to produce a panel the
    /// user cannot see or click.
    private static func read(
        _ defaults: UserDefaults,
        _ key: String,
        _ fallback: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard let stored = defaults.object(forKey: key) as? Double,
              range.contains(stored)
        else { return fallback }
        return stored
    }

    /// Restore every value to the shipped defaults. The folder is cleared too —
    /// a "reset" that left a stale bookmark behind would not read as a reset.
    func resetToDefaults() {
        capsuleWidth = 291
        capsuleHeight = 37.5
        expandedWidth = 640
        expandedHeight = 335
        hoverOpenDelay = 0.08
        hoverCloseDelay = 0.28
        storageFolderBookmark = nil
        rowStagger = 0.05
        workStartHour = 7
        workStartMinute = 30
        workEndHour = 17
        workEndMinute = 0
        workdays = [2, 3, 4, 5, 6]
        reminderEnabled = true
        reminderIntervalMinutes = 60
        reminderSoundEnabled = true
        aiBaseURL = "http://localhost:20128/v1"
        aiModel = "antigravity"
        aiApiKey = AIKeyResolver.liveGatewayKey() ?? ""
        syncWorkSchedule()
    }
}
