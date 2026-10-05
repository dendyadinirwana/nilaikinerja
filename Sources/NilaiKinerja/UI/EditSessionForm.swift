import SwiftUI
import AppKit

/// Edits an activity that is already recorded: its title, detail, and — the
/// part that actually matters for a report — the outcome.
///
/// This is the screen reached by swiping a row and tapping "Rekap". It is
/// separate from `AddActivityForm` because the two do different jobs: one
/// records *when* something happened, the other records *what came of it*.
/// A session that has no outcome is flagged "belum diisi" in the list and
/// excluded from the report until this is filled in.
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
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        // No local header: the universal notch tab bar is rendered by
        // NotchSurface, so this form is body content only.
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    summary
                    fields
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }

            Spacer(minLength: 0)
            actions
        }
    }


    /// When the work happened. Read-only here — the add form owns timing, and
    /// letting two screens edit the same field guarantees they disagree.
    private var summary: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.60))

            Text("\(Self.clock.string(from: session.startedAt))–\(Self.clock.string(from: session.endedAt ?? Date()))")
                .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.90))

            Spacer(minLength: 0)

            if !session.isReportable {
                Label("belum terisi", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0xFBBF24))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.12), lineWidth: 0.5)
                )
        )
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(
                "Judul kegiatan",
                symbol: "pencil.line",
                height: 40,
                hasText: !draft.title.isEmpty
            ) {
                ZStack(alignment: .leading) {
                    if draft.title.isEmpty {
                        Text("Tanpa judul")
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.38))
                    }
                    TextField("", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.96))
                }
            }

            field(
                "Rincian",
                symbol: "text.alignleft",
                height: 64,
                hasText: !draft.detail.isEmpty
            ) {
                ZStack(alignment: .topLeading) {
                    if draft.detail.isEmpty {
                        Text("Opsional")
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.38))
                            .padding(.top, 1)
                    }
                    TextField("", text: $draft.detail, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14.5))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .lineLimit(2...3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }

            // The outcome is what the report actually cites, so it gets the
            // most emphasis and a placeholder that says what belongs here.
            field(
                "Hasil",
                symbol: "checkmark.seal.fill",
                height: 64,
                hasText: !draft.outcome.isEmpty
            ) {
                ZStack(alignment: .topLeading) {
                    if draft.outcome.isEmpty {
                        Text("Contoh: 3 draft SIPPDT selesai direview")
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.38))
                            .padding(.top, 1)
                    }
                    TextField("", text: $draft.outcome, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14.5))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .lineLimit(2...3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private func field<Content: View>(
        _ label: String,
        symbol: String = "",
        height: CGFloat? = nil,
        hasText: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: 0x16181F))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(
                                    hasText ? Color(hex: 0x60A5FA).opacity(0.45) : Color.white.opacity(0.14),
                                    lineWidth: 0.8
                                )
                        )
                )
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            iconButton("Batal", "xmark", prominent: false, action: onCancel)
            Spacer(minLength: 0)
            iconButton("Simpan", "checkmark", prominent: true, action: save)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private func save() {
        // `markRecorded` is what lifts the "belum diisi" flag and admits the
        // row to the report, so it is set whenever an outcome now exists.
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

/// Form state. `@StateObject` because the view struct is rebuilt on every
/// keystroke; an `@ObservedObject` default expression would construct a fresh
/// model each time and discard what was typed.
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
