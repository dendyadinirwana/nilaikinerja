import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Contextual tabs for organizing settings cleanly without endless scrolling.
enum SettingsTab: String, CaseIterable {
    case notch = "Notch & Interaksi"
    case ai = "Asisten AI"
    case schedule = "Kinerja & Berkas"
    case about = "Tentang"

    var icon: String {
        switch self {
        case .notch: return "display"
        case .ai: return "sparkles"
        case .schedule: return "checklist"
        case .about: return "info.circle"
        }
    }
}

/// Simple state holder avoiding SwiftUIMacros plugin requirement.
final class SettingsTabHolder: ObservableObject {
    @Published var selectedTab: SettingsTab = .notch
}

/// The settings panel: 3-state notch tuning, AI connection, schedule, and attachments.
///
/// Presented as a screen inside the expanded panel rather than a separate
/// window, so it inherits the notch's expansion animation and dismisses the
/// same way the other screens do.
struct SettingsScreen: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var aiService = AIChatService.shared
    @ObservedObject private var updateService = UpdateService.shared
    @ObservedObject private var permissionManager = SystemPermissionManager.shared
    @StateObject private var tabHolder = SettingsTabHolder()
    @Namespace private var settingsTabNamespace
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
        VStack(alignment: .leading, spacing: 0) {
            tabSwitcher
            Divider().overlay(Color.white.opacity(0.08))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    switch tabHolder.selectedTab {
                    case .notch:
                        notchInteractionTab
                    case .ai:
                        aiTab
                    case .schedule:
                        scheduleAndStorageTab
                    case .about:
                        aboutTab
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: tabHolder.selectedTab)
            }
            .frame(height: NotchGeometry.settingsBodyHeight - 48)

            Divider().overlay(Color.white.opacity(0.08))
            footer
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: NotchGeometry.settingsHeight
        )
    }

    // MARK: - Tab Switcher

    private var tabSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                let isSelected = tabHolder.selectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        tabHolder.selectedTab = tab
                    }
                } label: {
                    ZStack {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(Color(hex: 0x1E222A))
                                .matchedGeometryEffect(id: "settingsActiveTabIndicator", in: settingsTabNamespace)
                                .shadow(color: Color.black.opacity(0.35), radius: 4, y: 1)
                        } else {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        }

                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .foregroundStyle(isSelected ? Color(hex: 0x60A5FA) : Color.white.opacity(0.70))
                        .scaleEffect(isSelected ? 1.04 : 1.0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Tab 1: Notch & Interaksi

    private var notchInteractionTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            // State 1: Idle
            section("State 1 — Idle") {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Garis Tepi Glowing")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.white)
                        Text("Menampilkan garis tepi bercahaya lembut di sekeliling hardware notch saat idle.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 16)
                    Toggle("", isOn: $settings.idleGlowEnabled)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: Color(hex: 0x2563EB)))
                }

                if settings.idleGlowEnabled {
                    slider(
                        "Intensitas Cahaya",
                        value: $settings.idleGlowIntensity,
                        range: 0.2...1.0,
                        format: "%.0f%%",
                        multiplier: 100
                    )
                }
            }

            // State 2: Idle Hover
            section("State 2 — Idle Hover") {
                slider(
                    "Dwell Timer ke Expanded",
                    value: $settings.idleDwellDuration,
                    range: 0.3...2.0,
                    format: "%.2f dtk"
                )
                Text("Waktu kursor harus menetap di atas notch sebelum panel otomatis mekar ke bawah.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)

                slider(
                    "Lebar Kapsul",
                    value: $settings.capsuleWidth,
                    range: 220...360,
                    format: "%.0f pt"
                )
                slider(
                    "Tinggi Kapsul",
                    value: $settings.capsuleHeight,
                    range: 28...50,
                    format: "%.1f pt"
                )
            }

            // State 3: Expanded
            section("State 3 — Expanded") {
                slider(
                    "Lebar Panel Terbuka",
                    value: $settings.expandedWidth,
                    range: 520...720,
                    format: "%.0f pt"
                )
                slider(
                    "Auto-Collapse Delay",
                    value: $settings.hoverCloseDelay,
                    range: 0.1...2.0,
                    format: "%.2f dtk"
                )
                Text("Jeda waktu sebelum panel menutup otomatis kembali ke idle saat kursor ditinggalkan.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Tab 2: Asisten AI

    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            aiSection
        }
    }

    // MARK: - Tab 3: Kinerja & Berkas

    private var scheduleAndStorageTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            workScheduleSection
            reminderSection
            storageSection
        }
    }

    // MARK: - Tab 4: Tentang & Pembaruan

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // App Identity Header
            HStack(spacing: 14) {
                RobotHeadView(
                    state: .idle,
                    shape: .rectangle,
                    size: 50,
                    color: "#2563EB",
                    trimColor: "#93A6C8",
                    screenColor: "#E8F2FF",
                    antenna: false,
                    floorShadow: false
                )
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.04))
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("NilaiKinerja")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)

                        Text("v\(updateService.currentVersion)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x60A5FA))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule()
                                    .fill(Color(hex: 0x60A5FA).opacity(0.14))
                            )
                    }

                    Text("Pencatatan kinerja ASN berbasis notch MacBook.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.bottom, 2)

            // Update Card
            section("Pembaruan Perangkat Lunak (OTA)") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(updateStatusHeadline)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)

                            Text(updateStatusSubheadline)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.50))
                        }

                        Spacer(minLength: 12)

                        updateActionButton
                    }

                    // Changelog notes if an update is available
                    if case .available(let version, let notes, _) = updateService.status {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Catatan Rilis \(version)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: 0x60A5FA))
                            ScrollView(showsIndicators: true) {
                                Text(notes)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 70)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.04))
                            )
                        }
                    }

                    // Auto-check toggle
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Periksa Pembaruan Otomatis")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                            Text("Cek pembaruan di latar belakang saat aplikasi baru dibuka.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        Spacer(minLength: 16)
                        Toggle("", isOn: $settings.autoCheckUpdates)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: Color(hex: 0x2563EB)))
                    }
                    .padding(.top, 4)
                }
            }

            // System Permissions Status Card
            section("Izin & Akses Sistem macOS") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Aksesibilitas (Tracking & Drag-Drop)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                            Text("Dibutuhkan untuk memantau interaksi kursor di atas notch.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        Spacer(minLength: 16)
                        if permissionManager.isAccessibilityGranted {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Diizinkan")
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .foregroundStyle(Color(hex: 0x10B981))
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(
                                Capsule()
                                    .fill(Color(hex: 0x10B981).opacity(0.12))
                            )
                        } else {
                            Button {
                                permissionManager.openAccessibilitySettings()
                            } label: {
                                Text("Buka Pengaturan")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .frame(height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(hex: 0x2563EB))
                                    )
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(NotchPressStyle())
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.06))

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pemberitahuan Sistem (Notifikasi)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                            Text("Dibutuhkan untuk pengingat checkpoint kinerja berkala.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        Spacer(minLength: 16)
                        if permissionManager.isNotificationGranted {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Diizinkan")
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .foregroundStyle(Color(hex: 0x10B981))
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(
                                Capsule()
                                    .fill(Color(hex: 0x10B981).opacity(0.12))
                            )
                        } else {
                            Button {
                                permissionManager.requestNotificationPermission()
                            } label: {
                                Text("Minta Izin")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .frame(height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.white.opacity(0.12))
                                    )
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(NotchPressStyle())
                        }
                    }
                }
            }

            // Project & License Information
            section("Informasi Lisensi & Repositori") {
                VStack(alignment: .leading, spacing: 10) {
                    infoRow("Lisensi", value: "MIT License (100% Open Source)")
                    infoRow("Maskot 3D", value: "fayazara/robot-heads (Fayaz Ahmed)")
                    infoRow("Pengembang", value: "nirwna")

                    Button {
                        if let url = URL(string: "https://github.com/dendyadinirwana/nilaikinerja") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12))
                            Text("Buka Repositori di GitHub")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color(hex: 0x60A5FA))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Update Helpers

    private var updateStatusHeadline: String {
        switch updateService.status {
        case .idle:
            return "Versi Saat Ini: v\(updateService.currentVersion)"
        case .checking:
            return "Memeriksa Pembaruan..."
        case .upToDate:
            return "NilaiKinerja Sudah Versi Terbaru"
        case .available(let version, _, _):
            return "Pembaruan Tersedia: \(version)"
        case .downloading:
            return "Mengunduh Pembaruan..."
        case .readyToRelaunch:
            return "Pembaruan Siap Dipasang"
        case .error(let msg):
            return msg
        }
    }

    private var updateStatusSubheadline: String {
        switch updateService.status {
        case .idle, .upToDate:
            if let date = updateService.lastChecked {
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                return "Terakhir diperiksa pukul \(f.string(from: date))"
            }
            return "GitHub: dendyadinirwana/nilaikinerja"
        case .checking:
            return "Menghubungi api.github.com..."
        case .available:
            return "Klik Unduh & Pasang untuk memperbarui aplikasi."
        case .downloading(let progress):
            return "Progres: \(Int(progress * 100))%"
        case .readyToRelaunch:
            return "Mulai ulang sekarang untuk beralih ke versi baru."
        case .error:
            return "Pastikan perangkat terhubung ke internet."
        }
    }

    @ViewBuilder
    private var updateActionButton: some View {
        switch updateService.status {
        case .idle, .upToDate, .error:
            Button {
                updateService.checkForUpdates(explicit: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Periksa Pembaruan")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .padding(.horizontal, 14)
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

        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(.white)
                Text("Memeriksa...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(height: 36)
            .padding(.horizontal, 12)

        case .available:
            Button {
                updateService.downloadAndInstall()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Unduh & Pasang")
                        .font(.system(size: 12.5, weight: .bold))
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: 0x2563EB))
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(NotchPressStyle())

        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: Color(hex: 0x60A5FA)))
                    .frame(width: 80)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(height: 36)

        case .readyToRelaunch:
            Button {
                updateService.relaunchApp()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Mulai Ulang Aplikasi")
                        .font(.system(size: 12.5, weight: .bold))
                }
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: 0x059669))
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(NotchPressStyle())
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.60))
            Spacer()
            Text(value)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.90))
        }
    }

    // MARK: - Sections

    private var aiSection: some View {
        section("Asisten AI (OpenAI Compatible / 9router)") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Base URL API")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                    TextField("http://localhost:20128/v1", text: $settings.aiBaseURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                )
                        )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("API Key (Opsional)")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                    SecureField("Kosongkan jika gateway lokal tanpa auth", text: $settings.aiApiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                )
                        )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Model Default")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.70))
                    HStack(spacing: 8) {
                        TextField("antigravity", text: $settings.aiModel)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                )
                            )

                        Button {
                            Task {
                                await aiService.fetchModels(
                                    baseURL: settings.aiBaseURL,
                                    storedKey: settings.aiApiKey
                                )
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if aiService.isFetchingModels {
                                    ProgressView().controlSize(.mini).tint(.white)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                Text(aiService.isFetchingModels ? "Mengambil…" : "Daftar Model")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: 0x2563EB))
                            )
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(NotchPressStyle())
                        .disabled(aiService.isFetchingModels)
                    }
                }

                if !aiService.availableModels.isEmpty {
                    Text("Terdeteksi \(aiService.availableModels.count) model dari gateway.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(hex: 0x60A5FA))
                }
            }
        }
    }

    private var workScheduleSection: some View {
        section("Jadwal Kerja") {
            VStack(alignment: .leading, spacing: 14) {
                // Hari kerja
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hari Kerja Aktif")
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
                                    .frame(height: 36)
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
                    .foregroundStyle(.white.opacity(0.6))
                timeStepper(value: minute, range: 0...59, step: 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeStepper(
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        HStack(spacing: 4) {
            Text(String(format: "%02d", value.wrappedValue))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 26)

            VStack(spacing: 1) {
                Button {
                    let next = value.wrappedValue + step
                    value.wrappedValue = next > range.upperBound ? range.lowerBound : next
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 16, height: 11)
                }
                .buttonStyle(.plain)

                Button {
                    let prev = value.wrappedValue - step
                    value.wrappedValue = prev < range.lowerBound ? range.upperBound : prev
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 16, height: 11)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
    }

    private var reminderSection: some View {
        section("Pengingat Checkpoint") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pengingat Berkala")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.white)
                        Text("Buka notch otomatis untuk menanyakan progres pekerjaan.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 16)
                    Toggle("", isOn: $settings.reminderEnabled)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: Color(hex: 0x2563EB)))
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suara Notifikasi")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.white)
                        Text("Bunyikan suara halus saat waktu pengingat tiba.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 16)
                    Toggle("", isOn: $settings.reminderSoundEnabled)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: Color(hex: 0x2563EB)))
                }

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
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
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
        format: String,
        multiplier: Double = 1.0
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(String(format: format, value.wrappedValue * multiplier))
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Slider(value: value, in: range)
                .controlSize(.small)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Pilih Folder"
        panel.message = "Pilih folder untuk menyimpan lampiran kegiatan"

        if panel.runModal() == .OK, let url = panel.url {
            settings.setStorageFolder(url)
        }
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
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
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
                        .font(.system(size: 13.5, weight: .bold))
                }
                .padding(.horizontal, 18)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                )
                .foregroundStyle(Color(hex: 0x141518))
            }
            .buttonStyle(NotchPressStyle())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }
}
