import Foundation

/// Builds the daily and monthly performance reports.
///
/// The output follows the table layout an Indonesian ASN reviewer expects:
/// `No | Waktu | Kegiatan | Hasil | Dokumen`. The time column is a range, not
/// a point, because a report entry that says "09:00" invites the question
/// "sampai jam berapa?".
@MainActor
enum ReportBuilder {

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "HH.mm"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "EEEE, d MMMM yyyy"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let columns: [DocxWriter.Column] = [
        .init(header: "No", weight: 1, align: .center),
        .init(header: "Waktu", weight: 3, align: .center),
        .init(header: "Kegiatan", weight: 6, align: .left),
        .init(header: "Hasil", weight: 6, align: .left),
        .init(header: "Dokumen\nPendukung", weight: 4, align: .left)
    ]

    // MARK: - Daily

    @discardableResult
    static func daily(
        on date: Date,
        store: SessionStore,
        to destination: URL
    ) throws -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let all = store.sessions(in: DateInterval(start: start, end: end))
        let reportable = all.filter(\.isReportable)

        var paragraphs: [String] = []
        paragraphs.append("LAPORAN KINERJA HARIAN")
        paragraphs.append("")
        paragraphs.append("Tanggal: \(capitalized(dayFormatter.string(from: date)))")

        let totalMinutes = Int(reportable.reduce(0.0) { $0 + $1.duration } / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        paragraphs.append("Total Waktu Kerja: \(hours) jam \(minutes) menit")
        paragraphs.append("Jumlah Kegiatan: \(reportable.count) kegiatan")

        if reportable.isEmpty {
            paragraphs.append("")
            paragraphs.append("Belum ada kegiatan tercatat pada tanggal ini.")
        }

        var rows: [[String]] = []
        for (index, session) in reportable.enumerated() {
            let end = session.endedAt ?? session.startedAt.addingTimeInterval(session.duration)
            let timeRange = "\(formatter.string(from: session.startedAt)) - \(formatter.string(from: end))"

            let activity = ([session.title ?? ""]
                + (session.detail.map { ["", $0] } ?? []))
                .joined(separator: "\n")

            let outcome = session.outcome?.isEmpty == false
                ? session.outcome!
                : "—"

            let documents = (store.attachments[session.id] ?? [])
                .map(\.filename)
                .joined(separator: "\n")
            let documentCell = documents.isEmpty ? "—" : documents

            rows.append([
                String(index + 1),
                timeRange,
                activity,
                outcome,
                documentCell
            ])
        }

        if !rows.isEmpty {
            rows.append(["", "", "", "TOTAL", "\(hours)j \(minutes)m"])
        }

        try DocxWriter.write(
            paragraphs: paragraphs,
            table: rows.isEmpty ? [] : [(columns: columns, rows: rows)],
            to: destination
        )
        return reportable.count
    }

    // MARK: - Monthly

    @discardableResult
    static func monthly(
        in interval: DateInterval,
        store: SessionStore,
        to destination: URL
    ) throws -> Int {
        let all = store.sessions(in: interval).filter(\.isReportable)
        let calendar = Calendar.current

        // Group by calendar day, preserving chronological order.
        var byDay: [Date: [WorkSession]] = [:]
        for session in all {
            let day = calendar.startOfDay(for: session.startedAt)
            byDay[day, default: []].append(session)
        }
        let days = byDay.keys.sorted()

        var paragraphs: [String] = []
        paragraphs.append("REKAPITULASI KINERJA BULANAN")
        paragraphs.append("")
        paragraphs.append("Periode: \(capitalized(monthFormatter.string(from: interval.start)))")
        paragraphs.append("Jumlah Hari Aktif: \(days.count) hari")
        paragraphs.append("Jumlah Kegiatan: \(all.count) kegiatan")

        let totalMinutes = Int(all.reduce(0.0) { $0 + $1.duration } / 60)
        paragraphs.append("Total Waktu Kerja: \(totalMinutes / 60) jam \(totalMinutes % 60) menit")

        // A day-level summary, because a reviewer usually wants the shape of
        // the month before the detail.
        let dayFormatterShort = DateFormatter()
        dayFormatterShort.locale = Locale(identifier: "id_ID")
        dayFormatterShort.dateFormat = "dd/MM/yyyy"

        var dayRows: [[String]] = []
        for (index, day) in days.enumerated() {
            let sessions = byDay[day] ?? []
            let minutes = Int(sessions.reduce(0.0) { $0 + $1.duration } / 60)
            let activities = sessions
                .compactMap(\.title)
                .joined(separator: "; ")
            dayRows.append([
                String(index + 1),
                dayFormatterShort.string(from: day),
                String(sessions.count),
                "\(minutes / 60)j \(minutes % 60)m",
                activities
            ])
        }

        let dayColumns: [DocxWriter.Column] = [
            .init(header: "No", weight: 1, align: .center),
            .init(header: "Tanggal", weight: 3, align: .center),
            .init(header: "Jumlah\nKegiatan", weight: 2, align: .center),
            .init(header: "Waktu", weight: 2, align: .center),
            .init(header: "Kegiatan", weight: 9, align: .left)
        ]

        try DocxWriter.write(
            paragraphs: paragraphs,
            table: dayRows.isEmpty ? [] : [(columns: dayColumns, rows: dayRows)],
            to: destination
        )
        return all.count
    }

    // MARK: - Paths

    static func defaultExportDirectory() -> URL {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        let target = dir.appendingPathComponent("Nilai Kinerja", isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    static func dailyFilename(for date: Date) -> String {
        "Laporan Kinerja \(dayKeyFormatter.string(from: date)).docx"
    }

    static func monthlyFilename(for interval: DateInterval) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return "Rekapitulasi Kinerja \(f.string(from: interval.start)).docx"
    }

    /// `dayFormatter` yields "senin, 5 mei 2026"; official documents start the
    /// line with a capital.
    private static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }
}
