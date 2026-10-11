import SwiftUI
import AppKit

/// Form for viewing and editing details of an already recorded ASN activity:
/// Title, Time Range, Working Duration, Details, Outcomes, and Supporting Attachments.
struct EditSessionForm: View {
    let session: WorkSession
    let store: SessionStore
    let onSave: () -> Void
    let onCancel: () -> Void

    @StateObject private var draft: EditDraft

    init(session: WorkSession, store: SessionStore, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.session = session
        self.store = store
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = StateObject(
            wrappedValue: EditDraft(
                title: session.title ?? "",
                detail: session.detail ?? "",
                outcome: session.outcome ?? ""
            )
        )
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var attachments: [Attachment] {
        store.attachments[session.id] ?? []
    }

    private var durationLabel: String {
        let start = session.startedAt
        let end = session.endedAt ?? Date()
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) Menit"
        } else {
            let hours = minutes / 60
            let remainder = minutes % 60
            if remainder == 0 {
                return "\(hours) Jam"
            }
            return "\(hours) Jam \(remainder) Menit"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    fields
                    attachmentsSection
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }

            Spacer(minLength: 0)
            actions
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(hex: 0x60A5FA))
                Text("\(Self.clock.string(from: session.startedAt)) – \(Self.clock.string(from: session.endedAt ?? Date()))")
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(Color(hex: 0x60A5FA).opacity(0.12))
            )

            HStack(spacing: 5) {
                Image(systemName: "timer")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x38BDF8))
                Text(durationLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.90))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
            )

            Spacer(minLength: 0)

            if session.isRunning {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: 0x34D399))
                        .frame(width: 7, height: 7)
                    Text("Aktif")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x34D399))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color(hex: 0x064E3B).opacity(0.6))
                )
            } else if session.isReportable {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                    Text("Lengkap")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color(hex: 0x10B981))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color(hex: 0x10B981).opacity(0.12))
                )
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5))
                    Text("Belum Rekap")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color(hex: 0xFBBF24))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color(hex: 0xFBBF24).opacity(0.12))
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Judul Kegiatan", symbol: "pencil.line", height: 36, hasText: !draft.title.isEmpty) {
                ZStack(alignment: .leading) {
                    if draft.title.isEmpty {
                        Text("Nama kegiatan kinerja...")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                    TextField("", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.96))
                }
            }

            field("Rincian / Uraian Tugas", symbol: "text.alignleft", height: 56, hasText: !draft.detail.isEmpty) {
                ZStack(alignment: .topLeading) {
                    if draft.detail.isEmpty {
                        Text("Uraian proses atau langkah yang dikerjakan...")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .padding(.top, 1)
                    }
                    TextField("", text: $draft.detail, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(2...3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }

            field("Hasil / Output Capaian", symbol: "checkmark.seal.fill", height: 56, hasText: !draft.outcome.isEmpty) {
                ZStack(alignment: .topLeading) {
                    if draft.outcome.isEmpty {
                        Text("Contoh: 1 Draf Laporan selesai, 3 bahan tayang disiapkan...")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .padding(.top, 1)
                    }
                    TextField("", text: $draft.outcome, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(2...3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    // MARK: - Attachments Section

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(hex: 0x60A5FA))
                    Text("Dokumen Bukti Kinerja")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                if !attachments.isEmpty {
                    Text("\(attachments.count) berkas terlampir")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            if attachments.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("Belum ada berkas lampiran yang tercatat pada kegiatan ini.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.40))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(attachments) { att in
                        attachmentRow(att)
                    }
                }
            }
        }
    }

    private func attachmentRow(_ att: Attachment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName(for: att.filename))
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0x60A5FA))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(att.filename)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Text(formatBytes(att.bytes))
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 8)

            Button {
                let url = att.url
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                    Text("Finder")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                )
                .foregroundStyle(Color(hex: 0x60A5FA))
            }
            .buttonStyle(.plain)
            .help("Buka berkas di Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: 0x16181F))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func iconName(for filename: String) -> String {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext.fill"
        case "docx", "doc", "odt", "pages", "rtf": return "doc.text.fill"
        case "pptx", "ppt", "odp", "key": return "play.rectangle.fill"
        case "xlsx", "xls", "csv", "ods", "numbers": return "tablecells.fill"
        case "txt", "text", "md", "markdown": return "doc.plaintext.fill"
        default: return "photo.fill"
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }

    private func field<Content: View>(
        _ label: String,
        symbol: String = "",
        height: CGFloat? = nil,
        hasText: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if !symbol.isEmpty {
                    Image(systemName: symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(hasText ? Color(hex: 0x60A5FA) : Color.white.opacity(0.4))
                }
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.80))
            }

            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: 0x16181F))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    hasText ? Color(hex: 0x60A5FA).opacity(0.40) : Color.white.opacity(0.10),
                                    lineWidth: 0.8
                                )
                        )
                )
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                onCancel()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Batal")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(NotchPressStyle())

            Spacer(minLength: 0)

            Button {
                save()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text("Simpan Perubahan")
                        .font(.system(size: 12.5, weight: .bold))
                }
                .padding(.horizontal, 18)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: 0x2563EB))
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(NotchPressStyle())
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private func save() {
        store.update(
            sessionID: session.id,
            title: draft.trimmedTitle.isEmpty ? nil : draft.trimmedTitle,
            detail: draft.trimmedDetail,
            outcome: draft.trimmedOutcome,
            markRecorded: !draft.trimmedOutcome.isEmpty
        )
        onSave()
    }
}

/// Form state.
@MainActor
final class EditDraft: ObservableObject {
    @Published var title: String
    @Published var detail: String
    @Published var outcome: String

    init(title: String, detail: String, outcome: String) {
        self.title = title
        self.detail = detail
        self.outcome = outcome
    }

    private func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedTitle: String { clean(title) }
    var trimmedDetail: String { clean(detail) }
    var trimmedOutcome: String { clean(outcome) }
}
