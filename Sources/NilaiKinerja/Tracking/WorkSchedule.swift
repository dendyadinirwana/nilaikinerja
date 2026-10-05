import Foundation

/// Working-hours arithmetic.
///
/// A performance report is reviewed against the *working calendar*, not against
/// how long a timer was left running. Two hours of real work at 19:00, or a
/// session left open over lunch, inflate the number the reviewer sees and
/// discredit the whole report. Everything here clips a raw elapsed interval to
/// the hours the user is actually expected to be working.
enum WorkSchedule {

    /// Configurable working hours & days. Defaults to Mon–Fri, 07:30–17:00.
    static var startHour: Int = 7
    static var startMinute: Int = 30
    static var endHour: Int = 17
    static var endMinute: Int = 0
    static var activeWorkdays: Set<Int> = [2, 3, 4, 5, 6]

    static var startOfDay: Int { startHour * 3600 + startMinute * 60 }
    static var endOfDay: Int { endHour * 3600 + endMinute * 60 }
    static var secondsPerDay: Int { max(0, endOfDay - startOfDay) }

    /// Holiday dates, as `yyyy-MM-dd` in the user's local timezone. Empty by
    /// default; the user can fill it from Settings when public holidays apply.
    static var holidays: Set<String> = []

    struct Workday: Equatable {
        /// Seconds inside working hours, clipped to the intersection of
        /// `interval` and the workday.
        let worked: TimeInterval
        /// Seconds of the intersection that fell inside working hours. Same as
        /// `worked` here, but kept separate so future rules (breaks, core
        /// hours) can subtract without changing the shape.
        let inWindow: TimeInterval
        let wasWorkday: Bool

        var isEmpty: Bool { worked <= 0.5 }
    }

    /// Clips `interval` to working hours, summing across days.
    ///
    /// An interval spanning midnight is split per calendar day, so overnight
    /// work is credited to the day it happened and never counted twice.
    static func worked(in interval: DateInterval, calendar: Calendar = .current) -> TimeInterval {
        guard interval.end > interval.start else { return 0 }

        var total: TimeInterval = 0
        var dayStart = calendar.startOfDay(for: interval.start)

        // Guard against a pathological range; 10 years is far beyond any
        // plausible report period and prevents a long loop.
        var guardCount = 0
        while dayStart < interval.end && guardCount < 3660 {
            guardCount += 1
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? interval.end

            let window = window(for: dayStart, calendar: calendar)
            guard let window else {
                dayStart = dayEnd
                continue
            }

            let overlapStart = max(interval.start, window.start)
            let overlapEnd = min(interval.end, window.end)
            if overlapEnd > overlapStart {
                total += overlapEnd.timeIntervalSince(overlapStart)
            }
            dayStart = dayEnd
        }
        return total
    }

    /// Per-day breakdown, oldest first. Used by the daily report so each row
    /// shows that day's real working time rather than a wall-clock range.
    static func breakdown(
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [(day: Date, worked: TimeInterval)] {
        var result: [(Date, TimeInterval)] = []
        var dayStart = calendar.startOfDay(for: interval.start)
        var guardCount = 0

        while dayStart < interval.end && guardCount < 3660 {
            guardCount += 1
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? interval.end
            let slice = DateInterval(start: max(interval.start, dayStart), end: min(interval.end, dayEnd))
            let seconds = worked(in: slice, calendar: calendar)
            if seconds > 0.5 {
                result.append((dayStart, seconds))
            }
            dayStart = dayEnd
        }
        return result
    }

    /// The working window for a given calendar day, or nil on a weekend or
    /// declared holiday.
    static func window(for day: Date, calendar: Calendar = .current) -> DateInterval? {
        let weekday = calendar.component(.weekday, from: day)
        // Calendar weekday 1 = Sunday, 2 = Monday … 7 = Saturday.
        guard activeWorkdays.contains(weekday) else { return nil }
        guard !holidays.contains(dayKey(day, calendar: calendar)) else { return nil }

        let start = calendar.date(
            bySettingHour: startHour, minute: startMinute, second: 0, of: day
        ) ?? day
        let end = calendar.date(
            bySettingHour: endHour, minute: endMinute, second: 0, of: day
        ) ?? day

        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func isWorkday(_ date: Date, calendar: Calendar = .current) -> Bool {
        window(for: date, calendar: calendar) != nil
    }

    /// Total working time for the day `date` falls in, from every session that
    /// touches it. This is the number the capsule shows.
    static func totalWorked(
        on date: Date,
        sessions: [WorkSession],
        calendar: Calendar = .current
    ) -> TimeInterval {
        guard let window = window(for: date, calendar: calendar) else { return 0 }
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? window.end

        return sessions.reduce(0.0) { total, session in
            // Credit both finished and still-running sessions, but only the
            // part inside the day: an overnight run does not count twice.
            let end = session.endedAt ?? min(Date(), dayEnd)
            let slice = DateInterval(
                start: max(session.startedAt, dayStart),
                end: max(end, dayStart)
            )
            guard slice.end > slice.start else { return total }
            let overlapStart = max(slice.start, window.start)
            let overlapEnd = min(slice.end, window.end)
            guard overlapEnd > overlapStart else { return total }
            return total + overlapEnd.timeIntervalSince(overlapStart)
        }
    }

    /// Progress toward a nominal 8-hour day, clamped to 0…1.
    static func progress(
        worked: TimeInterval,
        target: TimeInterval = 8 * 3600
    ) -> Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, worked / target))
    }

    /// `07:30` style label for the seconds already worked today.
    static func label(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }

    /// True when `date` falls inside the 07:30–17:00 window on a workday. The
    /// counterpart to `worked`, used to decide whether a live clock is
    /// currently accumulating reportable time.
    static func isWithinWindow(
        _ date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard isWorkday(date, calendar: calendar) else { return false }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let seconds = Double((c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60)
        return seconds >= Double(startOfDay) && seconds < Double(endOfDay)
    }

    /// `HH:MM:SS`, for a live running clock. Unlike `label` this keeps a
    /// seconds field, because that is what makes a running timer read as
    /// running rather than as a stale value.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// Status icon name, chosen so the capsule is readable without hovering.
    static func statusSymbol(on date: Date, worked: TimeInterval, calendar: Calendar = .current) -> String {
        let weekday = calendar.component(.weekday, from: date)
        if !(2...6).contains(weekday) { return "calendar.badge.exclamationmark" }
        if holidays.contains(dayKey(date, calendar: calendar)) { return "beach.umblla.fill" }

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let secondsNow = Double(hour * 3600 + minute * 60)

        if secondsNow < Double(startOfDay) { return "moon.zzz.fill" }
        if secondsNow >= Double(endOfDay) { return "checkmark.seal.fill" }
        return "briefcase.fill"
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
