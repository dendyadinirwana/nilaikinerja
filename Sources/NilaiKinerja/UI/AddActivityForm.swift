import SwiftUI
import AppKit

/// The "Tambah kegiatan" form: a single sheet-style panel with a time range,
/// title, detail, and document drop, ending in Simpan / Batal.
///
/// It replaces the running-task form rather than living beside it, so the
/// expanded panel never shows two competing forms.
struct AddActivityForm: View {
    @ObservedObject var coordinator: TrackingCoordinator
    var initialTitle: String? = nil
    var initialDetail: String? = nil
    var initialURLs: [URL]? = nil
    var initialFrom: Date? = nil
    var initialTo: Date? = nil
    let onSave: () -> Void
    let onCancel: () -> Void

    @StateObject private var draft = ActivityDraft()

    var body: some View {
        // No local header: the universal notch tab bar is rendered by
        // NotchSurface, so this form is body content only.
        formBody
            .onAppear {
                draft.loadDefaults()
                if let initialTitle, !initialTitle.isEmpty {
                    draft.title = initialTitle
                }
                if let initialDetail, !initialDetail.isEmpty {
                    draft.detail = initialDetail
                }
                if let initialFrom {
                    draft.from = initialFrom
                }
                if let initialTo {
                    draft.to = initialTo
                }
                if let initialURLs, !initialURLs.isEmpty {
                    draft.add(initialURLs)
                }
            }
            .onChange(of: initialTitle) { _, newTitle in
                if let newTitle, !newTitle.isEmpty { draft.title = newTitle }
            }
            .onChange(of: initialURLs) { _, newURLs in
                if let newURLs, !newURLs.isEmpty { draft.add(newURLs) }
            }
    }

    private var formBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            timeRange
            titleField
            detailField
            attachmentArea
            Spacer(minLength: 0)
            actions
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Fields

    private var timeRange: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Waktu Kegiatan")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                HStack(spacing: 5) {
                    quickTimeChip("+15m") { addMinutes(15) }
                    quickTimeChip("+30m") { addMinutes(30) }
                    quickTimeChip("+1j") { addMinutes(60) }
                    quickTimeChip("Sekarang") { snapToNow() }
                }
            }

            HStack(spacing: 10) {
                timePickerBox(
                    title: "Mulai",
                    hour: fromHourBinding,
                    minute: fromMinuteBinding
                )

                VStack(spacing: 3) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x60A5FA).opacity(0.6))

                    Text(draft.durationLabel)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(draft.isValid ? Color(hex: 0x60A5FA) : Color(hex: 0xFBBF24))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule()
                                .fill(draft.isValid ? Color(hex: 0x60A5FA).opacity(0.15) : Color(hex: 0xFBBF24).opacity(0.15))
                        )
                }
                .frame(width: 58)

                timePickerBox(
                    title: "Selesai",
                    hour: toHourBinding,
                    minute: toMinuteBinding
                )
            }
        }
    }

    private func timePickerBox(
        title: String,
        hour: Binding<Int>,
        minute: Binding<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.70))

            HStack(spacing: 6) {
                timeStepper(value: hour, range: 0...23, step: 1)
                Text(":")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.40))
                timeStepper(value: minute, range: 0...55, step: 5)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(hex: 0x16181F))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                    )
            )
        }
    }

    private func timeStepper(value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        HStack(spacing: 4) {
            Text(String(format: "%02d", value.wrappedValue))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 26)

            VStack(spacing: 2) {
                Button {
                    let cur = value.wrappedValue
                    let remainder = cur % step
                    let next = remainder == 0 ? cur + step : cur + (step - remainder)
                    if next <= range.upperBound {
                        value.wrappedValue = next
                    } else {
                        value.wrappedValue = range.lowerBound
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: 0x60A5FA).opacity(0.85))

                Button {
                    let cur = value.wrappedValue
                    let remainder = cur % step
                    let prev = remainder == 0 ? cur - step : cur - remainder
                    if prev >= range.lowerBound {
                        value.wrappedValue = prev
                    } else {
                        value.wrappedValue = range.upperBound
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: 0x60A5FA).opacity(0.85))
            }
        }
    }

    private var fromHourBinding: Binding<Int> {
        Binding(
            get: {
                Calendar.current.component(.hour, from: draft.from)
            },
            set: { newHour in
                let cal = Calendar.current
                draft.from = cal.date(bySettingHour: newHour, minute: cal.component(.minute, from: draft.from), second: 0, of: draft.from) ?? draft.from
            }
        )
    }

    private var fromMinuteBinding: Binding<Int> {
        Binding(
            get: {
                Calendar.current.component(.minute, from: draft.from)
            },
            set: { newMinute in
                let cal = Calendar.current
                draft.from = cal.date(bySettingHour: cal.component(.hour, from: draft.from), minute: newMinute, second: 0, of: draft.from) ?? draft.from
            }
        )
    }

    private var toHourBinding: Binding<Int> {
        Binding(
            get: {
                Calendar.current.component(.hour, from: draft.to)
            },
            set: { newHour in
                let cal = Calendar.current
                draft.to = cal.date(bySettingHour: newHour, minute: cal.component(.minute, from: draft.to), second: 0, of: draft.to) ?? draft.to
            }
        )
    }

    private var toMinuteBinding: Binding<Int> {
        Binding(
            get: {
                Calendar.current.component(.minute, from: draft.to)
            },
            set: { newMinute in
                let cal = Calendar.current
                draft.to = cal.date(bySettingHour: cal.component(.hour, from: draft.to), minute: newMinute, second: 0, of: draft.to) ?? draft.to
            }
        )
    }

    private func quickTimeChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(Color(hex: 0x16181F))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                        )
                )
        }
        .buttonStyle(NotchPressStyle())
    }

    private func addMinutes(_ mins: Int) {
        let calendar = Calendar.current
        draft.to = calendar.date(byAdding: .minute, value: mins, to: draft.from) ?? draft.to
    }

    private func snapToNow() {
        let calendar = Calendar.current
        let now = Date()
        let minute = calendar.component(.minute, from: now)
        let rounded = (minute / 5) * 5
        let floored = calendar.date(bySetting: .minute, value: rounded, of: calendar.date(bySetting: .second, value: 0, of: now) ?? now) ?? now
        draft.to = floored
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Judul kegiatan")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            shell(height: 40, hasText: !draft.title.isEmpty) {
                ZStack(alignment: .leading) {
                    if draft.title.isEmpty {
                        Text("Contoh: Review dokumen SIPPDT")
                            .font(.system(size: 14.5, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.38))
                    }
                    TextField("", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.96))
                }
            }
        }
    }

    private var detailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Rincian / hasil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("(Opsional)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.40))
            }

            shell(height: 64, hasText: !draft.detail.isEmpty) {
                ZStack(alignment: .topLeading) {
                    if draft.detail.isEmpty {
                        Text("Catatan atau rincian capaian kegiatan...")
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
        }
    }

    private func shell<Content: View>(height: CGFloat? = nil, hasText: Bool = false, @ViewBuilder content: () -> Content) -> some View {
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

    // MARK: - Attachments

    private var attachmentArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Dokumen pendukung")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()
                if !draft.attachments.isEmpty {
                    Text("\(draft.attachments.count) berkas dilampirkan")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x60A5FA))
                }
            }

            dropZone

            if !draft.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(draft.attachments) { item in
                            chip(item)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: 0x60A5FA).opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: draft.attachments.isEmpty ? "arrow.down.doc.fill" : "doc.badge.plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(hex: 0x60A5FA))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.attachments.isEmpty ? "Seret dokumen ke sini" : "Tambah dokumen lain")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text("PDF, gambar PNG atau JPG (maks. 25MB)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer(minLength: 0)

                Button {
                    pickFiles()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 11.5))
                        Text("Pilih Berkas")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.white.opacity(0.16), lineWidth: 0.8)
                            )
                    )
                    .foregroundStyle(.white.opacity(0.95))
                }
                .buttonStyle(NotchPressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            Color(hex: 0x60A5FA).opacity(0.25),
                            style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                        )
                )
        )
        .background(AttachmentDropView { urls in draft.add(urls) })
    }

    private func chip(_ item: ActivityDraft.Attachment) -> some View {
        HStack(spacing: 5) {
            Image(systemName: item.kind == .pdf ? "doc.richtext.fill" : "photo.fill")
                .font(.system(size: 11))
            Text(item.filename)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Button {
                draft.attachments.removeAll { $0.id == item.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.08))
        )
        .foregroundStyle(.white.opacity(0.85))
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            iconButton("Batal", "xmark", prominent: false, action: onCancel)
                .disabled(draft.isSaving || draft.showSuccess)
            Spacer(minLength: 0)
            if draft.showValidation, !draft.validationHint.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(draft.validationHint)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0xFBBF24))
            }
            if draft.showSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Tersimpan!")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(
                    Capsule().fill(Color(hex: 0x059669))
                )
                .foregroundStyle(.white)
                .transition(.scale.combined(with: .opacity))
            } else if draft.isSaving {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 14, height: 14)
                    Text("Menyimpan...")
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(
                    Capsule().fill(Color.white.opacity(0.12))
                )
                .foregroundStyle(.white.opacity(0.85))
            } else {
                iconButton("Simpan", "checkmark", prominent: true) {
                    save()
                }
            }
        }
    }

    // MARK: - Actions impl

    private func save() {
        guard !draft.isSaving, !draft.showSuccess else { return }
        guard draft.isValid else {
            // Reveal the reason only after an attempt, not while the form is
            // still untouched.
            draft.showValidation = true
            NSSound.beep()
            return
        }

        draft.isSaving = true

        let saved = draft.persist(using: coordinator.store)
        if saved {
            NSSound(named: "Glass")?.play()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                draft.showSuccess = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onSave()
            }
        } else {
            draft.isSaving = false
            NSSound.beep()
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .pdf]
        panel.prompt = "Lampirkan"
        // Capture the draft directly: this is a value-type view, so there is
        // no `self` worth weak-referencing, and the draft is what needs to
        // outlive the sheet.
        let draft = draft
        // The notch panel is a non-activating accessory window, so the open
        // panel has to be brought forward explicitly.
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK else { return }
            MainActor.assumeIsolated {
                draft.add(panel.urls)
            }
        }
    }
}

/// Form state. `ObservableObject` rather than `@State` because `@State` is a
/// Swift 6 macro whose plugin ships only with Xcode.
@MainActor
final class ActivityDraft: ObservableObject {
    struct Attachment: Identifiable {
        let id = UUID()
        let filename: String
        let path: String
        // Fully qualified: inside this nested scope a bare `Attachment` would
        // resolve to `ActivityDraft.Attachment` rather than the model type.
        let kind: NilaiKinerja.Attachment.Kind
        let bytes: Int
        let sha: String
    }

    @Published var title: String = ""
    @Published var detail: String = ""
    @Published var from: Date = Date()
    @Published var to: Date = Date()
    @Published var attachments: [Attachment] = []
    @Published var isSaving: Bool = false
    @Published var showSuccess: Bool = false

    private let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Defaults to the last hour, which is what someone adding an activity
    /// usually means. Adjustable, and any other choice is respected.
    ///
    /// Rounded to the minute because the pickers display hour-and-minute: a
    /// range ending at, say, 10:47:31 would render as "10:47" and look like
    /// a zero-length range next to a start rounded the same way.
    func loadDefaults() {
        let calendar = Calendar.current
        let now = Date()
        let minute = calendar.component(.minute, from: now)
        let rounded = (minute / 5) * 5
        let floored = calendar.date(
            bySetting: .minute, value: rounded,
            of: calendar.date(bySetting: .second, value: 0, of: now) ?? now
        ) ?? now
        let start = calendar.date(byAdding: .minute, value: -60, to: floored) ?? floored
        to = floored
        from = start
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && to > from
    }

    /// Only surfaced once the user has actually tried to save. Showing it on
    /// an untouched form is noise — the form already looks empty.
    @Published var showValidation: Bool = false

    var validationHint: String {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Judul wajib diisi" }
        if to <= from { return "Waktu akhir harus setelah mulai" }
        return ""
    }

    var durationLabel: String {
        let minutes = Int(to.timeIntervalSince(from) / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)j \(minutes % 60)m"
    }

    /// Copies dropped files into app storage and records them for the draft.
    /// Mirrors what the live session does so behaviour is identical whether a
    /// document is attached now or later.
    func add(_ urls: [URL]) {
        for url in urls {
            guard let stored = try? AttachmentStore.store(url) else { continue }
            // Re-adding the same document within one draft is a no-op.
            guard !attachments.contains(where: { $0.sha == stored.sha256 }) else { continue }
            attachments.append(
                Attachment(
                    filename: stored.filename,
                    path: stored.path,
                    kind: stored.kind,
                    bytes: stored.bytes,
                    sha: stored.sha256
                )
            )
        }
    }

    @discardableResult
    func persist(using store: SessionStore) -> Bool {
        store.logPastActivity(
            title: title,
            detail: detail.isEmpty ? nil : detail,
            outcome: nil,
            from: from,
            to: to,
            attachments: attachments.map {
                (filename: $0.filename, path: $0.path, kind: $0.kind, bytes: $0.bytes, sha: $0.sha)
            }
        ) != nil
    }
}
