import SwiftUI
import AppKit

@MainActor
final class AIChatDraft: ObservableObject {
    @Published var inputText: String = ""
    @Published var copyFeedback: String? = nil

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyFeedback = "Tersalin ke clipboard"
        NSSound(named: "Glass")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.copyFeedback == "Tersalin ke clipboard" {
                self?.copyFeedback = nil
            }
        }
    }
}

/// The Coucou-inspired floating AI chat surface inside the MacBook notch.
struct AIChatView: View {
    @ObservedObject var settings: AppSettings
    let onDismiss: () -> Void
    let onLogAsActivity: (String) -> Void

    @ObservedObject private var service = AIChatService.shared
    @StateObject private var draft = AIChatDraft()

    private let quickPrompts = [
        "Buatkan draf kegiatan penyusunan pedoman umum SIPPDT",
        "Buat laporan rekap capaian kinerja harian ASN",
        "Formulasikan indikator target kinerja Ditjen PPDT"
    ]

    var body: some View {
        // The local tool row (sparkles icon, "Asisten AI", the model pill and
        // the trash button) was removed: the universal notch tab bar above
        // already names the section, so the row repeated it and cost 44pt of
        // vertical space for controls that belong at the input. The model
        // selector moved down to the input bar as a dropdown; clearing the
        // conversation is reachable from the menu-bar item.
        VStack(alignment: .leading, spacing: 0) {
            if let error = service.errorMessage {
                errorBanner(error)
            }

            if let copyToast = draft.copyFeedback {
                toastBanner(copyToast)
            }

            messageArea

            Divider().opacity(0.12)
            inputBar
        }
        .onAppear {
            if service.availableModels.isEmpty {
                Task {
                    await service.fetchModels(baseURL: settings.aiBaseURL, storedKey: settings.aiApiKey)
                }
            }
        }
    }

    // MARK: - Message Area

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                if service.messages.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(service.messages) { msg in
                            messageRow(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .onChange(of: service.messages.count) { _, _ in
                if let last = service.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: service.messages.last?.content) { _, _ in
                if let last = service.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x2563EB).opacity(0.3), Color(hex: 0x60A5FA).opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color(hex: 0x60A5FA))
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(quickPrompts, id: \.self) { prompt in
                    Button {
                        draft.inputText = prompt
                        submitMessage()
                    } label: {
                        HStack {
                            Text(prompt)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func messageRow(_ msg: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.role == .user {
                Spacer(minLength: 32)
                MarkdownInlineText(
                    text: msg.content,
                    font: .system(size: 13.5, weight: .medium),
                    color: .white
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: 0x1E3A8A).opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(hex: 0x3B82F6).opacity(0.4), lineWidth: 0.6)
                        )
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: 0x60A5FA))
                        Text(settings.aiModel)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    if !msg.thinkingContent.isEmpty {
                        ThinkingDisclosureView(
                            thinking: msg.thinkingContent,
                            isStreaming: msg.isThinking
                        )
                    }

                    if msg.isThinking && msg.content.isEmpty && msg.thinkingContent.isEmpty {
                        ThinkingIndicatorView()
                    } else if !msg.content.isEmpty {
                        MarkdownContentView(markdown: msg.content)
                    }

                    if !msg.content.isEmpty {
                        HStack(spacing: 12) {
                            Button {
                                draft.copyToClipboard(msg.content)
                            } label: {
                                Label("Salin", systemImage: "doc.on.doc")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .buttonStyle(.plain)

                            Button {
                                onLogAsActivity(msg.content)
                            } label: {
                                Label("Catat ke Kinerja", systemImage: "plus.circle")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0x60A5FA))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
                Spacer(minLength: 24)
            }
        }
    }

    // MARK: - Model Selector

    /// Dropdown model selector.
    ///
    /// Replaces both the header pill and the full-height picker drawer it used
    /// to toggle. The drawer replaced the whole message area, so choosing a
    /// model meant losing sight of the conversation — a menu scoped to the
    /// input bar keeps both visible and needs no open/close state.
    private var modelMenu: some View {
        ModelSelectorMenu(
            settings: settings,
            service: service
        )
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                TextField("Tanya AI notch (misal: draf laporan kegiatan)…", text: $draft.inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white)
                    .onSubmit { submitMessage() }

                if service.isStreaming {
                    Button {
                        service.stopStreaming()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: 0xEF4444))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: submitMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(draft.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                          ? Color.white.opacity(0.12)
                                          : Color(hex: 0x2563EB))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
            )

            // Replaces the old "9router • <url>" / "Enter untuk kirim" line.
            // The provider footer was debug residue — the endpoint is already
            // editable in Settings, and the send hint duplicated the obvious.
            // `borderlessButton` centres its label in the available width, so
            // the row has to be told to lead. `.fixedSize()` on the menu itself
            // stops the capsule from stretching across the bar — without it the
            // trailing padding pushes the chevron away from the model name.
            modelMenu
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func submitMessage() {
        let text = draft.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft.inputText = ""
        service.sendMessage(
            text,
            baseURL: settings.aiBaseURL,
            storedKey: settings.aiApiKey,
            model: settings.aiModel
        )
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0xF87171))
            Text(msg)
                .font(.system(size: 11.5))
                .foregroundStyle(Color(hex: 0xFCA5A5))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(hex: 0x7F1D1D).opacity(0.4))
    }

    private func toastBanner(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0x34D399))
            Text(msg)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.95))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(Color(hex: 0x065F46).opacity(0.7))
    }
}

// MARK: - Model Selector Menu

/// Dropdown model selector, extracted from `AIChatView` so `--aipickdump` can
/// render it. Rendering the label alone showed a perfectly coloured chevron,
/// which meant the corruption came from the `Menu` wrapper — so the diagnostic
/// has to include the wrapper to see it.
/// `@State` cannot be used in this build — the `SwiftUIMacros` plugin is not
/// loaded, so `@State` fails to expand. An `ObservableObject` holder is the
/// established workaround in this file.
final class PopoverToggle: ObservableObject {
    @Published var isShowing = false
}

struct ModelSelectorMenu: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var service: AIChatService
    @StateObject private var popoverState = PopoverToggle()

    private let commonModels = ["antigravity", "chatgpt", "claude", "grok", "gemini/gemini-3.8-flash"]

    var body: some View {
        // A plain `Button` plus a popover, not `Menu`.
        //
        // `Menu` was swallowing the label outright. `--aipickdump` rendered the
        // bare label and the `Menu`-wrapped copy side by side: the bare one
        // showed dot, name and blue chevron; the wrapped one drew nothing at
        // all. Three theories were tried and all three were wrong — template
        // images, alpha too low, alignment — so the label can no longer be
        // handed to a control that owns its own rendering.
        Button {
            popoverState.isShowing.toggle()
        } label: {
            ModelSelectorLabel(model: settings.aiModel.isEmpty ? "antigravity" : settings.aiModel)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $popoverState.isShowing, arrowEdge: .bottom) {
            modelList
        }
    }

    private var modelList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Favorit")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 5)

            ForEach(commonModels, id: \.self) { model in
                modelRow(model)
            }

            if !service.availableModels.isEmpty {
                Divider().opacity(0.1).padding(.vertical, 6)

                Text("Terdeteksi (\(service.availableModels.count))")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 5)

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(service.availableModels, id: \.self) { model in
                            modelRow(model)
                        }
                    }
                }
                .frame(maxHeight: 220)
            } else {
                Divider().opacity(0.1).padding(.vertical, 6)

                Button {
                    Task {
                        await service.fetchModels(
                            baseURL: settings.aiBaseURL,
                            storedKey: settings.aiApiKey
                        )
                    }
                } label: {
                    HStack(spacing: 6) {
                        if service.isFetchingModels {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(service.isFetchingModels ? "Mengambil dari 9router…" : "Refresh Daftar Model")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: 0x60A5FA))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(service.isFetchingModels)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 268)
        .background(Color(hex: 0x16181F))
    }

    private func modelRow(_ model: String) -> some View {
        let selected = settings.aiModel == model
        return Button {
            settings.aiModel = model
            popoverState.isShowing = false
        } label: {
            HStack(spacing: 8) {
                Text(model)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(selected ? Color(hex: 0x60A5FA) : .white.opacity(0.8))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: 0x60A5FA))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(ModelRowButtonStyle(isSelected: selected))
    }
}

/// Row highlight for the popover. `Button` needs its own style here because the
/// default one draws a system bezel that fights the dark panel.
private struct ModelRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected
                          ? Color(hex: 0x60A5FA).opacity(0.12)
                          : Color.white.opacity(configuration.isPressed ? 0.12 : 0))
            )
            .padding(.horizontal, 6)
    }
}

// MARK: - Model Selector Label

/// The pill shown inside the model `Menu`.
///
/// Kept as its own view so `--aipickdump` can rasterise it in isolation. Two
/// earlier attempts to diagnose the missing icon colour by reasoning about
/// `menuStyle` were both wrong; the only way to settle whether the chevron
/// renders was to look at the pixels.
struct ModelSelectorLabel: View {
    let model: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: 0x60A5FA))
                .frame(width: 6, height: 6)
            Text(model)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            ChevronDown()
                .fill(Color(hex: 0x60A5FA))
                .frame(width: 7, height: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
                )
        )
    }
}

// MARK: - Chevron

/// Downward triangle drawn as a `Shape` instead of `Image(systemName:)`.
private struct ChevronDown: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Thinking Indicator

@MainActor
final class ThinkingPulseState: ObservableObject {
    @Published var activeIndex: Int = 0
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.activeIndex = (self.activeIndex + 1) % 3
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}

struct ThinkingIndicatorView: View {
    @StateObject private var pulseState = ThinkingPulseState()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x60A5FA))

            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color(hex: 0x60A5FA))
                        .frame(width: 4.5, height: 4.5)
                        .opacity(pulseState.activeIndex == i ? 1.0 : 0.35)
                        .scaleEffect(pulseState.activeIndex == i ? 1.25 : 0.85)
                }
            }

            Text("Sedang berpikir...")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color(hex: 0x93C5FD).opacity(0.90))
        }
        .padding(.vertical, 4)
    }
}

