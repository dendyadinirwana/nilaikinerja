import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The settings panel: schedule, reminder, geometry, hover timing, and the attachment folder.
///
/// Presented as a screen inside the expanded panel rather than a separate
/// window, so it inherits the notch's expansion animation and dismisses the
/// same way the other screens do.
struct SettingsScreen: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var aiService = AIChatService.shared
    /// Switches back to the list when the user is done.
    var onDone: () -> Void

    private let dayOptions: [(Int, String)] = [
        (2, "Sen"),
        (3, "Sel"),
        (4, "Rab"),
        (5, "Kam"),
        (6, "Jum"),
        (7, "Sab"),
        (1, "Min"),
    ]

    private let reminderPresets: [Int] = [15, 30, 45, 60, 90]

    var body: some View {
        // The universal notch tab bar (rendered by NotchSurface) replaces the
        // old "Pengaturan" title row, including the close button — the gear
        // toggle in that bar already returns to Beranda.
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    aiSection
                    workScheduleSection
                    reminderSection
                    geometrySection
                    hoverSection
                    animationSection
                    storageSection
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .frame(height: NotchGeometry.settingsBodyHeight)

            Divider().overlay(Color.white.opacity(0.08))
            footer
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: NotchGeometry.settingsHeight
        )
    }

    // MARK: - Chrome

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                settings.resetToDefaults()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Kembalikan Default")
                        .font(.system(size: 13.5, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
                .foregroundStyle(.white.opacity(0.75))
            }
            .buttonStyle(NotchPressStyle())

            Spacer()

            Button {
                onDone()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                    Text("Selesai")
                        .font(.system(size: 14, weight: .bold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                )
                .foregroundStyle(Color.black)
            }
            .buttonStyle(NotchPressStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Sections

    private var aiSection: some View {
        section("Integrasi AI") {
            VStack(alignment: .leading, spacing: 14) {
                // Base URL
                VStack(alignment: .leading, spacing: 6) {
                    Text("Base URL Endpoint")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))

                    TextField("http://localhost:20128/v1", text: $settings.aiBaseURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: 0x16181F))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                                )
                        )
                }

                // API Key
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key / Bearer Token")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))

                    SecureField("Token otentikasi (sk-…)", text: $settings.aiApiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: 0x16181F))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                                )
                        )
                }

                // Model Default & Test Button
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Model Default")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))

                        Spacer()

                        if !aiService.availableModels.isEmpty {
                            Text("\(aiService.availableModels.count) model")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(hex: 0x60A5FA))
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("antigravity", text: $settings.aiModel)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: 0x16181F))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                                    )
                            )

                        testConnectionButton
                    }

                    // Model presets
                    HStack(spacing: 6) {
                        ForEach(["antigravity", "chatgpt", "claude", "grok", "gemini/gemini-3.8-flash"], id: \.self) { m in
                            let isSelected = settings.aiModel == m
                            Button {
                                settings.aiModel = m
                            } label: {
                                Text(m.components(separatedBy: "/").last ?? m)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))
                                    .foregroundStyle(isSelected ? Color(hex: 0x60A5FA) : .white.opacity(0.70))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color(hex: 0x60A5FA).opacity(0.15) : Color(hex: 0x16181F))
                                            .overlay(
                                                Capsule()
                                                    .stroke(isSelected ? Color(hex: 0x60A5FA).opacity(0.40) : Color.white.opacity(0.12), lineWidth: 0.6)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)

                    if let status = aiService.statusInfo {
                        Text(status)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0x34D399))
                            .padding(.top, 2)
                    } else if let err = aiService.errorMessage {
                        Text(err)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xF87171))
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private var testConnectionButton: some View {
        Button {
            Task {
                let res = await aiService.testConnection(
                    baseURL: settings.aiBaseURL,
                    storedKey: settings.aiApiKey,
                    model: settings.aiModel
                )
                if res != "ok" {
                    aiService.statusInfo = nil
                    aiService.errorMessage = "Gagal: \(res)"
                }
            }
        } label: {
            ZStack {
                if aiService.isStreaming {
                    ProgressView()
                        .scaleEffect(0.65)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0x60A5FA))
                }
            }
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: 0x16181F))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(NotchPressStyle())
        .help("Uji koneksi ke endpoint AI")
    }

    private var workScheduleSection: some View {
        section("Waktu Kerja") {
            VStack(alignment: .leading, spacing: 12) {
                // Hari kerja selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hari Kerja")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))

                    HStack(spacing: 6) {
                        ForEach(dayOptions, id: \.0) { day, name in
                            let isSelected = settings.workdays.contains(day)
                            Button {
                                if isSelected {
                                    if settings.workdays.count > 1 {
                                        settings.workdays.removeAll { $0 == day }
                                    }
                                } else {
                                    settings.workdays.append(day)
                                    settings.workdays.sort()
                                }
                            } label: {
                                Text(name)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSelected ? Color(hex: 0x2563EB) : Color.white.opacity(0.06))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(isSelected ? Color(hex: 0x60A5FA) : Color.white.opacity(0.12), lineWidth: 0.5)
                                            )
                                    )
                                    .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("\(settings.workdays.count) hari kerja aktif per minggu")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.48))
                }

                // Jam kerja pickers
                HStack(spacing: 12) {
                    timePickerBox(
                        title: "Mulai Kerja",
                        hour: $settings.workStartHour,
                        minute: $settings.workStartMinute
                    )

                    timePickerBox(
                        title: "Selesai Kerja",
                        hour: $settings.workEndHour,
                        minute: $settings.workEndMinute
                    )
                }
            }
        }
    }

    private func timePickerBox(
        title: String,
        hour: Binding<Int>,
        minute: Binding<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 6) {
                timeStepper(value: hour, range: 0...23, step: 1)
                Text(":")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                timeStepper(value: minute, range: 0...55, step: 5)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.12), lineWidth: 0.5)
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
                    if value.wrappedValue + step <= range.upperBound {
                        value.wrappedValue += step
                    } else {
                        value.wrappedValue = range.lowerBound
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.65))

                Button {
                    if value.wrappedValue - step >= range.lowerBound {
                        value.wrappedValue -= step
                    } else {
                        value.wrappedValue = range.upperBound
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.65))
            }
        }
    }

    private var reminderSection: some View {
        section("Pengingat (Reminder)") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $settings.reminderEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ingatkan Catat Kegiatan")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Text("Pemberitahuan berkala untuk mencatat pekerjaan harian.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: 0x2563EB)))

                if settings.reminderEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Interval Pengingat")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.70))

                        HStack(spacing: 8) {
                            ForEach(reminderPresets, id: \.self) { minutes in
                                let isSelected = settings.reminderIntervalMinutes == minutes
                                Button {
                                    settings.reminderIntervalMinutes = minutes
                                } label: {
                                    Text("\(minutes) mnt")
                                        .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? Color(hex: 0x2563EB) : Color.white.opacity(0.06))
                                                .overlay(
                                                    Capsule()
                                                        .stroke(isSelected ? Color(hex: 0x60A5FA) : Color.white.opacity(0.12), lineWidth: 0.5)
                                                )
                                        )
                                        .foregroundStyle(isSelected ? .white : .white.opacity(0.70))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var geometrySection: some View {
        section("Ukuran") {
            slider(
                "Lebar idle",
                value: $settings.capsuleWidth,
                range: 220...420,
                format: "%.0f pt"
            )
            slider(
                "Tinggi idle & header",
                value: $settings.capsuleHeight,
                range: 28...56,
                format: "%.1f pt"
            )
            slider(
                "Lebar panel",
                value: $settings.expandedWidth,
                range: 360...720,
                format: "%.0f pt"
            )
            slider(
                "Tinggi panel",
                value: $settings.expandedHeight,
                range: 260...620,
                format: "%.0f pt"
            )
        }
    }

    private var hoverSection: some View {
        section("Hover & Respon") {
            slider(
                "Buka setelah",
                value: $settings.hoverOpenDelay,
                range: 0...1.0,
                format: "%.2f dtk"
            )
            slider(
                "Tutup setelah",
                value: $settings.hoverCloseDelay,
                range: 0...2.0,
                format: "%.2f dtk"
            )
            Text("Jeda tutup mencegah panel tertutup saat kursor bergerak dari capsule ke daftar.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var animationSection: some View {
        section("Animasi") {
            slider(
                "Stagger baris",
                value: $settings.rowStagger,
                range: 0...0.12,
                format: "%.3f dtk"
            )
            Text("Jeda kemunculan bertahap antar kegiatan saat panel terbuka.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var storageSection: some View {
        section("Folder Penyimpanan") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: 0x60A5FA))
                    Text(folderDisplayPath)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(
                            settings.storageFolderURL == nil
                                ? Color.white.opacity(0.60)
                                : Color.white.opacity(0.90)
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button {
                        pickFolder()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 12))
                            Text(settings.storageFolderURL == nil ? "Pilih…" : "Ganti")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.white.opacity(0.12), lineWidth: 0.5)
                                )
                        )
                        .foregroundStyle(.white.opacity(0.92))
                    }
                    .buttonStyle(NotchPressStyle())
                }

                Text("Lampiran kegiatan dan laporan harian disimpan di folder ini.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
    }

    private var folderDisplayPath: String {
        if let url = settings.storageFolderURL {
            let path = url.path
            let home = NSHomeDirectory()
            if path.hasPrefix(home) {
                return "~" + path.dropFirst(home.count)
            }
            return path
        }
        return "~/Documents (Bawaan)"
    }

    // MARK: - Building blocks

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 11.5, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.48))
            content()
        }
    }

    private func slider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Slider(value: value, in: range)
                .controlSize(.small)
                .tint(Color(hex: 0x60A5FA))
        }
    }

    // MARK: - Folder picker

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Simpan di sini"
        panel.message = "Lampiran kegiatan dan laporan harian akan disimpan di folder ini."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        // A cancelled pick leaves the existing bookmark alone; a granted one
        // that failed to encode also leaves it, so a failure here is a no-op
        // rather than a silent reset.
        settings.setStorageFolder(url)
    }
}
