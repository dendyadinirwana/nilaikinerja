import SwiftUI
import AppKit

/// Transient hover state for the header bar, avoiding Swift 6 @State macro.
@MainActor
final class HeaderBarUIState: ObservableObject {
    @Published var hoveredTab: PanelMode.Screen? = nil
    @Published var isHoveringSettings: Bool = false
    @Published var isHoveringSound: Bool = false
}

/// Unified top control bar for the expanded notch, matching the Coucou island header.
/// Hosts left tab capsules (Home/Mochi, Kegiatan, Tanya AI, Tambah) and
/// right utilities (Pengaturan, Suara).
struct NotchHeaderBar: View {
    @ObservedObject var mode: PanelMode
    @ObservedObject var settings: AppSettings
    @Namespace private var tabNamespace
    @StateObject private var uiState = HeaderBarUIState()

    private var barHeight: CGFloat {
        min(CGFloat(settings.capsuleHeight), NotchGeometry.expandedChromeHeight - 60)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Tab capsules
            HStack(spacing: 6) {
                tabButton(icon: "house.fill", screen: .home, label: "Beranda Mochi")
                tabButton(icon: "checklist", screen: .list, label: "Kegiatan Hari Ini")
                tabButton(icon: "bubble.left.fill", screen: .chat, label: "Tanya AI")
                tabButton(icon: "plus", screen: .add, label: "Tambah Kegiatan")
            }
            .padding(.leading, 12)

            Spacer()

            // Right: Utility icons
            HStack(spacing: 6) {
                // Settings button
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        mode.screen = (mode.screen == .settings) ? .home : .settings
                    }
                } label: {
                    ZStack {
                        if mode.screen == .settings {
                            Capsule(style: .continuous)
                                .fill(Color(hex: 0x1E222A))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color(hex: 0x60A5FA).opacity(0.45), lineWidth: 0.8)
                                )
                        } else if uiState.isHoveringSettings {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        }

                        Image(systemName: mode.screen == .settings ? "gearshape.fill" : "gearshape")
                            .font(.system(size: 13.5, weight: mode.screen == .settings ? .semibold : .regular))
                            .foregroundStyle(mode.screen == .settings ? Color(hex: 0x60A5FA) : (uiState.isHoveringSettings ? .white : Color(hex: 0x8E939C)))
                    }
                    .frame(width: 38, height: max(24, barHeight - 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        uiState.isHoveringSettings = h
                    }
                }
                .help("Pengaturan")

                // Mute/Unmute sound button
                Button {
                    settings.reminderSoundEnabled.toggle()
                    if settings.reminderSoundEnabled {
                        NSSound(named: "Glass")?.play()
                    }
                } label: {
                    ZStack {
                        if uiState.isHoveringSound {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        }

                        Image(systemName: settings.reminderSoundEnabled ? "speaker.wave.2" : "speaker.slash")
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(uiState.isHoveringSound ? .white : Color(hex: 0x8E939C))
                    }
                    .frame(width: 38, height: max(24, barHeight - 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        uiState.isHoveringSound = h
                    }
                }
                .help(settings.reminderSoundEnabled ? "Suara Aktif" : "Suara Hening")
            }
            .padding(.trailing, 14)
        }
        .frame(height: barHeight)
    }

    private func tabButton(icon: String, screen: PanelMode.Screen, label: String) -> some View {
        let isOn = mode.screen == screen
        let isHovered = uiState.hoveredTab == screen
        let capsuleHeight = max(24, barHeight - 10)

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                if mode.screen == .add && screen != .add {
                    mode.prefillAddTitle = nil
                    mode.prefillAddDetail = nil
                }
                mode.screen = screen
            }
        } label: {
            ZStack {
                // Sliding active pill
                if isOn {
                    Capsule(style: .continuous)
                        .fill(Color(hex: 0x1E222A))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color(hex: 0x60A5FA).opacity(0.45), lineWidth: 0.9)
                        )
                        .matchedGeometryEffect(id: "headerActiveTabIndicator", in: tabNamespace)
                        .shadow(color: Color(hex: 0x60A5FA).opacity(0.18), radius: 6, y: 1)
                } else if isHovered {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
                        )
                }

                Image(systemName: icon)
                    .font(.system(size: 13, weight: isOn ? .bold : .medium))
                    .foregroundStyle(
                        isOn
                            ? Color(hex: 0x60A5FA)
                            : (isHovered ? Color.white : Color(hex: 0x8E939C))
                    )
                    .scaleEffect(isOn ? 1.08 : (isHovered ? 1.04 : 1.0))
            }
            .frame(width: 44, height: capsuleHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                if h {
                    uiState.hoveredTab = screen
                } else if uiState.hoveredTab == screen {
                    uiState.hoveredTab = nil
                }
            }
        }
        .help(label)
    }
}
