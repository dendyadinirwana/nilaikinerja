import SwiftUI

/// The notch surface: one shape that morphs between a collapsed capsule and an
/// expanded panel inside a fixed canvas.
///
/// Collapsed shows the character (left) and the working-hours timer (right).
/// Expanded shows today's activity list with "Tambah kegiatan" at the bottom.
/// One morph keeps it liquid.
struct NotchSurface: View {
    @ObservedObject var coordinator: TrackingCoordinator
    @ObservedObject var form: CheckpointForm
    @ObservedObject var motion: NotchMotion
    @ObservedObject var mode: PanelMode
    @ObservedObject var today: TodaySummary
    @ObservedObject var settings: AppSettings
    /// The entrance stagger. Held here rather than created per row because one
    /// cascade per panel is what makes the rows arrive in sequence; a per-row
    /// instance would give every row a delay of zero.
    @ObservedObject var reveal: RevealCascade
    let isNotched: Bool
    let visualState: NotchVisualState
    let hardwareNotchSize: CGSize
    let collapsedSize: CGSize
    let onExpandNow: () -> Void
    let onDrop: ([URL]) -> Void
    /// Reports the size actually being presented so the window's click-through
    /// region matches the visible shape on every screen and at every width.
    let onPresentedSize: (CGSize, Bool) -> Void

    var isExpanded: Bool { visualState == .expanded }

    init(
        coordinator: TrackingCoordinator,
        form: CheckpointForm,
        mode: PanelMode,
        today: TodaySummary,
        settings: AppSettings,
        reveal: RevealCascade,
        motion: NotchMotion,
        isNotched: Bool,
        visualState: NotchVisualState,
        hardwareNotchSize: CGSize,
        collapsedSize: CGSize,
        onExpandNow: @escaping () -> Void = {},
        onDrop: @escaping ([URL]) -> Void,
        onPresentedSize: @escaping (CGSize, Bool) -> Void = { _, _ in }
    ) {
        self.coordinator = coordinator
        self.form = form
        self.mode = mode
        self.today = today
        self.settings = settings
        self.reveal = reveal
        // Seed the cascade now: `onChange` only fires on a *change*, so without
        // this the stored stagger would be ignored until the user moved the
        // slider — the setting would look broken on a fresh launch.
        reveal.stagger = settings.rowStagger
        self.motion = motion
        self.isNotched = isNotched
        self.visualState = visualState
        self.hardwareNotchSize = hardwareNotchSize
        self.collapsedSize = collapsedSize
        self.onExpandNow = onExpandNow
        self.onDrop = onDrop
        self.onPresentedSize = onPresentedSize
    }

    private var targetSize: CGSize {
        switch visualState {
        case .idle:
            return hardwareNotchSize
        case .idleHover:
            return collapsedSize
        case .expanded:
            let panelWidth = CGFloat(settings.expandedWidth)
            switch mode.screen {
            case .settings:
                return CGSize(width: panelWidth, height: NotchGeometry.settingsHeight)
            case .add:
                return CGSize(width: panelWidth, height: NotchGeometry.addFormHeight)
            case .edit:
                return CGSize(width: panelWidth, height: NotchGeometry.editFormHeight)
            case .checkpoint:
                return CGSize(width: panelWidth, height: NotchGeometry.checkpointHeight)
            case .home:
                let h = mode.isHomeFormOpen ? NotchGeometry.homeWithFormHeight : NotchGeometry.homeHeight
                return CGSize(width: panelWidth, height: h)
            case .chat:
                return CGSize(width: panelWidth, height: NotchGeometry.chatHeight)
            case .list:
                if today.sessions.isEmpty {
                    return CGSize(width: panelWidth, height: NotchGeometry.emptyListHeight)
                } else {
                    let rows = min(today.sessions.count, NotchGeometry.maxVisibleRows)
                    let height = NotchGeometry.expandedChromeHeight + CGFloat(rows) * NotchGeometry.rowPitch
                    return CGSize(width: panelWidth, height: min(height, NotchGeometry.canvasSize.height))
                }
            }
        }
    }

    private var shape: UnevenRoundedRectangle {
        let top = isNotched ? 0 : targetSize.height / 2
        let bottom: CGFloat
        switch visualState {
        case .idle:
            bottom = isNotched ? 11 : targetSize.height / 2
        case .idleHover:
            bottom = NotchGeometry.collapsedRadius(isNotched: isNotched, height: targetSize.height)
        case .expanded:
            bottom = NotchGeometry.expandedRadius
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(Color(red: 0, green: 0, blue: 0))
                .overlay {
                    if visualState == .idle {
                        if settings.idleGlowEnabled {
                            shape.stroke(
                                Color(hex: 0x60A5FA).opacity(settings.idleGlowIntensity),
                                lineWidth: 1.2
                            )
                            .shadow(color: Color(hex: 0x60A5FA).opacity(settings.idleGlowIntensity * 0.75), radius: 5, y: 1.5)
                        }
                    } else {
                        shape.stroke(
                            Color.white.opacity(isExpanded ? 0.12 : 0.08),
                            lineWidth: 0.5
                        )
                    }
                }
                .shadow(
                    color: isExpanded
                        ? .black.opacity(0.55)
                        : (visualState == .idle && settings.idleGlowEnabled ? Color(hex: 0x60A5FA).opacity(settings.idleGlowIntensity * 0.4) : .clear),
                    radius: isExpanded ? 22 : 5,
                    y: isExpanded ? 10 : 2
                )

            ZStack(alignment: .top) {
                // Collapsed content (character + task counter) stays anchored under the notch
                collapsedContent
                    .frame(width: collapsedSize.width, height: collapsedSize.height)
                    .frame(maxWidth: targetSize.width, alignment: .top)
                    .opacity(visualState == .idleHover ? 1 : 0)
                    .scaleEffect(visualState == .idleHover ? 1.0 : (isExpanded ? 0.94 : 0.85), anchor: .top)
                    .animation(.easeOut(duration: 0.16), value: visualState)
                    .allowsHitTesting(visualState == .idleHover)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onExpandNow()
                    }

                // Expanded content (header, activity list, forms, settings)
                expandedContent
                    .frame(width: targetSize.width, height: targetSize.height, alignment: .topLeading)
                    .opacity(isExpanded ? 1 : 0)
                    .offset(y: isExpanded ? 0 : -8)
                    .animation(
                        isExpanded
                            ? .easeOut(duration: 0.22).delay(0.08)
                            : .easeIn(duration: 0.10),
                        value: isExpanded
                    )
                    .allowsHitTesting(isExpanded)
            }
            .frame(width: targetSize.width, height: targetSize.height, alignment: .topLeading)
            .clipped()
        }
        .frame(width: targetSize.width, height: targetSize.height, alignment: .topLeading)
        .animation(
            .spring(response: 0.44, dampingFraction: 0.78, blendDuration: 0.2),
            value: visualState
        )
        .animation(
            .spring(response: 0.44, dampingFraction: 0.78, blendDuration: 0.2),
            value: targetSize
        )
        // Restart the entrance cascade on every open. Without this the token
        // stays put after the first expand, so a later reopen shows the rows
        // already settled — the stagger plays exactly once per session.
        .onChange(of: visualState) { _, state in
            if state == .expanded { reveal.restart() }
            onPresentedSize(targetSize, state == .expanded)
        }
        .onChange(of: targetSize) { _, size in
            onPresentedSize(size, isExpanded)
        }
        .onAppear {
            onPresentedSize(targetSize, isExpanded)
        }
        // Keep the cascade in step with the setting. Pushing it here rather
        // than binding into `RevealCascade` directly means one owner decides
        // the value, and the object stays a plain animation clock.
        .onChange(of: settings.rowStagger) { _, value in
            reveal.stagger = value
        }
    }

    // MARK: - Collapsed

    /// Character on the left, live timer hard right.
    ///
    /// Two numbers, because they answer different questions. The large one is
    /// raw elapsed time and always runs — pausing it outside office hours
    /// would make the indicator look broken. The small badge is time inside
    /// the working window, which is the figure that goes in a report.
    ///
    /// The `Spacer` is load-bearing: without it the timer sits against the
    /// character and the capsule reads as one left-aligned blob. The clock
    /// being the rightmost element is what makes it scannable — the eye lands
    /// on the far edge for a time, the way a menu bar does.
    private var collapsedContent: some View {
        HStack(spacing: 0) {
            // Mini 3D TV robot head inside the collapsed capsule.
            LiveCharacterView(
                state: today.isWorkingNow ? .working : .idle,
                pointSize: 22
            )
            .padding(.leading, 14)
            .padding(.top, 5)
            .padding(.bottom, 5)

            Spacer(minLength: 8)

            taskCountCluster
                .padding(.trailing, 16)
        }
        .frame(width: collapsedSize.width, height: collapsedSize.height)
    }

    private var taskCountCluster: some View {
        HStack(spacing: 4) {
            Image(systemName: "checklist")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color(hex: 0x60A5FA))

            Text("\(today.recordedCount)")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
    }

    // MARK: - Expanded

    @ViewBuilder
    /// The tab bar is hoisted here rather than declared inside each screen, so the
    /// header is universal by construction: a screen cannot forget to render it,
    /// and two screens cannot drift apart visually. Screens supply only their
    /// body content.
    private var expandedContent: some View {
        VStack(spacing: 0) {
            NotchHeaderBar(mode: mode, settings: settings)
            Divider().opacity(0.12)
            screenBody
        }
    }

    @ViewBuilder
    private var screenBody: some View {
        switch mode.screen {
        case .home:
            homeScreen
        case .list:
            listScreen
        case .add:
            AddActivityForm(
                coordinator: coordinator,
                initialTitle: mode.prefillAddTitle,
                initialDetail: mode.prefillAddDetail,
                initialURLs: mode.prefillAddURLs,
                initialFrom: mode.prefillAddFrom,
                initialTo: mode.prefillAddTo,
                onSave: {
                    mode.prefillAddTitle = nil
                    mode.prefillAddDetail = nil
                    mode.prefillAddURLs = nil
                    mode.prefillAddFrom = nil
                    mode.prefillAddTo = nil
                    today.refresh()
                    mode.showToast("Kegiatan berhasil ditambahkan")
                    mode.screen = .list
                },
                onCancel: {
                    mode.prefillAddTitle = nil
                    mode.prefillAddDetail = nil
                    mode.prefillAddURLs = nil
                    mode.prefillAddFrom = nil
                    mode.prefillAddTo = nil
                    mode.screen = .list
                }
            )
        case .chat:
            AIChatView(
                settings: settings,
                onDismiss: {
                    mode.screen = .list
                },
                onLogAsActivity: { summary in
                    mode.prefillAddTitle = "Draf Tugas / Catatan AI"
                    mode.prefillAddDetail = summary
                    mode.screen = .add
                }
            )
        case .edit:
            if let session = mode.editing {
                EditSessionForm(
                    session: session,
                    store: coordinator.store,
                    onSave: {
                        today.refresh()
                        mode.showToast("Perubahan berhasil disimpan")
                        mode.editing = nil
                        mode.screen = .list
                    },
                    onCancel: {
                        mode.editing = nil
                        mode.screen = .list
                    }
                )
            } else {
                // The row vanished between the swipe and this render. Fall
                // back rather than showing a blank panel.
                listScreen
            }
        case .checkpoint:
            checkpointScreen
        case .settings:
            SettingsScreen(settings: settings) {
                mode.screen = .home
            }
        }
    }

    /// Front stage companion view featuring Mochi mascot matching Coucou.
    private var homeScreen: some View {
        VStack(spacing: 0) {
            if mode.isHomeFormOpen {
                mochiHomeFormView
            } else {
                MochiStageView(
                    settings: settings,
                    coordinator: coordinator,
                    mode: mode,
                    onNavigateToTasks: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            mode.screen = .list
                        }
                    },
                    onNavigateToChat: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            mode.screen = .chat
                        }
                    }
                )
            }
        }
    }

    private var mochiHomeFormView: some View {
        VStack(spacing: 6) {
            // Big Animated Mochi Companion Hero Card (Height: 114pt)
            HStack(spacing: 14) {
                // Large full animated Mochi mascot
                MochiAnimatedHeroView(
                    state: .happy,
                    scale: 1.0
                )
                    .frame(width: 140, height: 104)
                    .padding(.leading, 6)

                // Companion speech / drop notification card
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Berkas Diterima")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                mode.isHomeFormOpen = false
                                mode.prefillAddTitle = nil
                                mode.prefillAddDetail = nil
                                mode.prefillAddURLs = nil
                                mode.prefillAddFrom = nil
                                mode.prefillAddTo = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.40))
                        }
                        .buttonStyle(.plain)
                        .help("Tutup Form")
                    }

                    if let file = mode.prefillAddURLs?.first?.lastPathComponent {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: 0x60A5FA))
                            Text(file)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.06))
                        )
                    }

                    Text("Waktu kegiatan otomatis disetel 1 jam. Tinjau judul & rincian di bawah lalu simpan.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                }
                .padding(.trailing, 12)
            }
            .frame(height: 114)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: 0x141518))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(hex: 0x60A5FA).opacity(0.35), lineWidth: 1.0)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.top, 2)

            // Add Activity Form body inline on Mochi screen
            AddActivityForm(
                coordinator: coordinator,
                initialTitle: mode.prefillAddTitle,
                initialDetail: mode.prefillAddDetail,
                initialURLs: mode.prefillAddURLs,
                initialFrom: mode.prefillAddFrom,
                initialTo: mode.prefillAddTo,
                onSave: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        mode.isHomeFormOpen = false
                        mode.prefillAddTitle = nil
                        mode.prefillAddDetail = nil
                        mode.prefillAddURLs = nil
                        mode.prefillAddFrom = nil
                        mode.prefillAddTo = nil
                    }
                    today.refresh()
                    mode.showToast("Kegiatan berhasil ditambahkan")
                    mode.screen = .list
                },
                onCancel: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        mode.isHomeFormOpen = false
                        mode.prefillAddTitle = nil
                        mode.prefillAddDetail = nil
                        mode.prefillAddURLs = nil
                        mode.prefillAddFrom = nil
                        mode.prefillAddTo = nil
                    }
                }
            )
        }
    }

    /// Default expanded view: today's activities, then bottom action buttons.
    private var listScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let toast = mode.toastMessage {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: 0x34D399))
                    Text(toast)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.95))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: 0x064E3B).opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(hex: 0x10B981).opacity(0.4), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if today.sessions.isEmpty {
                emptyList
            } else {
                activityList
                    .frame(height: CGFloat(min(today.sessions.count, NotchGeometry.maxVisibleRows)) * NotchGeometry.rowPitch)
                    .clipped()
            }

            bottomBar
        }
    }

    private var activityList: some View {
        let visibleCount = min(today.sessions.count, NotchGeometry.maxVisibleRows)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(today.sessions.enumerated()), id: \.element.id) { index, session in
                    staggered(index: index) {
                        row(for: session, pose: index == 0 ? rowPose : nil)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(height: CGFloat(visibleCount) * NotchGeometry.rowPitch)
    }

    /// Screenshot pose for the activity rows, set by the `--demo-swipe-*`
    /// flags so the drawer can be inspected without a real pointer. Only the
    /// first row poses; the rest stay closed for contrast.
    private var rowPose: String? {
        switch mode.demoSwipePose {
        case "open": return "open"
        case "leap": return "leap"
        default: return nil
        }
    }

    /// Wraps a list row in its slice of the entrance cascade.
    ///
    /// The row starts slightly low and transparent and settles into place on a
    /// spring, so the list reads as items arriving in sequence rather than as a
    /// block that appeared.
    @ViewBuilder
    private func staggered<Content: View>(
        index: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let delay = 0.08 + Double(min(index, 4)) * settings.rowStagger
        content()
            .opacity(isExpanded ? 1 : 0)
            .offset(y: isExpanded ? 0 : 12)
            .animation(
                isExpanded
                    ? .spring(response: 0.38, dampingFraction: 0.76).delay(delay)
                    : .easeOut(duration: 0.10),
                value: isExpanded
            )
    }

    private func row(for session: WorkSession, pose: String?) -> some View {
        // Swipe left to reveal Hapus (full swipe) and Rekap. Deleting is the
        // primary because it is the one destructive action here; Rekap is
        // secondary because it opens an editor rather than destroying work.
        // `Action` is nested inside the generic `SwipeRow`, so it has to be
        // spelled through a concrete specialization. `AnyView` is the smallest
        // one that satisfies the compiler without duplicating the row's own
        // layout in the type.
        SwipeRow<AnyView>(
            actions: [
                SwipeRow<AnyView>.Action(
                    id: "delete",
                    label: "Hapus",
                    symbol: "trash.fill",
                    isPrimary: true
                ),
                SwipeRow<AnyView>.Action(
                    id: "rekap",
                    label: "Rekap",
                    symbol: "square.and.pencil"
                )
            ],
            // Rekap is dispatched from `onAction`, not `onCommit`: it does not
            // fold the row, it opens the editor and leaves the row standing.
            onAction: { action in
                guard action.id == "rekap" else { return }
                mode.editing = session
                mode.screen = .edit
            },
            onCommit: { action in
                guard action.id == "delete" else { return }
                coordinator.store.delete(sessionID: session.id)
                today.refresh()
                mode.showToast("Kegiatan dihapus")
            },
            height: 74,
            radius: 14,
            actionWidth: 80,
            marginBottom: 14,
            // Tapping the row body is the primary way to read a session: the
            // swipe actions are for Hapus and Rekap, so a plain press opens the
            // same editor Rekap does.
            onTap: {
                mode.editing = session
                mode.screen = .edit
            },
            pose: pose
        ) {
            HStack(alignment: .top, spacing: 12) {
                // A filled emerald dot marks the running session, while a hollow
                // ring marks finished sessions (clear status affordance).
                if session.isRunning {
                    Circle()
                        .fill(Color(hex: 0x34D399))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                } else {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title ?? "Tanpa judul")
                        .font(.system(size: 16, weight: session.isRunning ? .bold : .semibold))
                        .foregroundStyle(session.isRunning ? .white : .white.opacity(0.94))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("\(today.timeLabel(session.startedAt))–\(today.timeLabel(session.endedAt ?? today.referenceDate))")
                            .foregroundStyle(.white.opacity(0.72))

                        Text(WorkSchedule.label(today.workedSeconds(for: session)))
                            .foregroundStyle(Color(hex: 0x60A5FA))
                            .fontWeight(.semibold)

                        if !session.isReportable {
                            Text("belum diisi")
                                .foregroundStyle(Color(hex: 0xFBBF24))
                        }
                    }
                    .font(.system(size: 13.5, weight: .medium))
                }

                Spacer(minLength: 0)

                let count = today.attachmentCount(for: session).count
                if count > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "paperclip")
                        Text("\(count)")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.60))
                    .padding(.top, 4)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.30))
                    .padding(.top, 6)
            }
            .padding(.horizontal, 14)
            .frame(height: 74)
            .frame(maxWidth: .infinity, alignment: .leading)

            // `Content` is fixed to `AnyView` at the call site so the nested
            // `Action` type is nameable there; the concrete `HStack` is erased
            // at this single boundary rather than duplicated.
            .eraseToAnyView()
        }
    }

    private var emptyList: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 48, height: 48)
                Image(systemName: "tray")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color(hex: 0x60A5FA).opacity(0.85))
            }
            .padding(.bottom, 2)

            Text("Belum ada kegiatan hari ini")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
            Text("Tekan tombol + di pojok kanan bawah untuk mencatat pekerjaan")
                .font(.system(size: 13.5))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    /// Bottom-right action row.
    /// Only the add CTA lives here. The gear was redundant — the notch header bar
    /// already carries a settings toggle one row above.
    private var bottomBar: some View {
        HStack(spacing: 10) {
            Spacer()

            Button {
                mode.screen = .add
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: 0x3B82F6), Color(hex: 0x1D4ED8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.8)
                            )
                    )
                    .shadow(color: Color(hex: 0x2563EB).opacity(0.45), radius: 6, y: 2)
            }
            .buttonStyle(NotchPressStyle())
            .help("Tambah kegiatan")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .padding(.top, 4)
    }

    /// Live-timer form for the running session.
    private var checkpointScreen: some View {
        // No local header: the universal notch tab bar is rendered above.
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    labelledField
                    suggestions
                    dropHint
                }
                .padding(16)
            }

            Spacer(minLength: 0)
            HStack(spacing: 8) {
                iconButton("Lanjut", "checkmark.circle.fill", prominent: true, action: confirm)
                iconButton("Ganti", "arrow.triangle.2.circlepath", prominent: false, action: switchTask)
                Spacer(minLength: 0)
                iconButton("Lewati", "forward.end.fill", prominent: false) { coordinator.skip() }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
    }

    private var dropHint: some View {
        HStack(spacing: 7) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text("Lampirkan dokumen")
                    .font(.system(size: 10, weight: .medium))
                Text("Seret gambar atau PDF ke sini")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(
                            .white.opacity(0.2),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                )
        )
        .background(AttachmentDropView { urls in onDrop(urls) })
    }


    private var labelledField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Judul pekerjaan")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            TextField("Contoh: Review dokumen SIPPDT", text: $form.title)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
                .onSubmit { confirm() }

            Text("Rincian")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            TextField("Opsional", text: $form.detail, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(2...3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: 56)
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

    @ViewBuilder
    private var suggestions: some View {
        let recent = coordinator.store.titleSuggestions(limit: 6)
        if !recent.isEmpty, form.title.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(recent, id: \.self) { item in
                        Button { form.title = item } label: {
                            Text(item)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(.white.opacity(0.09)))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 24)
        }
    }

    // MARK: - Actions

    private func confirm() {
        guard !form.trimmedTitle.isEmpty else { return }
        coordinator.confirm(
            title: form.trimmedTitle,
            detail: form.optionalDetail,
            outcome: form.optionalOutcome
        )
        mode.screen = .list
    }

    private func switchTask() {
        coordinator.switchTask(
            title: form.trimmedTitle,
            detail: form.optionalDetail,
            outcome: form.optionalOutcome
        )
        mode.screen = .list
    }
}

/// Which screen the expanded panel shows. Shared so the view and the window
/// controller agree on what is open.
@MainActor
final class PanelMode: ObservableObject {
    enum Screen { case home, list, add, edit, checkpoint, settings, chat }
    @Published var screen: Screen = .home
    /// The row being edited. Set before switching to `.edit`; ignored
    /// otherwise, so it cannot desynchronise from what is on screen.
    @Published var editing: WorkSession?
    /// Screenshot pose for the activity rows, driven by `--demo-swipe-*`.
    /// `nil` in normal use — the gesture owns the row.
    @Published var demoSwipePose: String?
    /// Temporary toast message shown on the list screen.
    @Published var toastMessage: String?
    /// Preloaded title/detail transferred from AI chat or templates.
    @Published var prefillAddTitle: String? = nil
    @Published var prefillAddDetail: String? = nil
    @Published var prefillAddURLs: [URL]? = nil
    @Published var prefillAddFrom: Date? = nil
    @Published var prefillAddTo: Date? = nil
    @Published var isHomeFormOpen: Bool = false

    /// Cycles to the next tab to the right (.home -> .list -> .chat -> .add -> .home)
    func nextTab() {
        let tabs: [Screen] = [.home, .list, .chat, .add]
        guard let idx = tabs.firstIndex(of: screen) else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                screen = .home
            }
            return
        }
        let nextIdx = (idx + 1) % tabs.count
        let targetScreen = tabs[nextIdx]
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            if screen == .add && targetScreen != .add {
                prefillAddTitle = nil
                prefillAddDetail = nil
            }
            screen = targetScreen
        }
    }

    /// Cycles to the previous tab to the left (.add -> .chat -> .list -> .home -> .add)
    func previousTab() {
        let tabs: [Screen] = [.home, .list, .chat, .add]
        guard let idx = tabs.firstIndex(of: screen) else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                screen = .home
            }
            return
        }
        let prevIdx = (idx - 1 + tabs.count) % tabs.count
        let targetScreen = tabs[prevIdx]
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            if screen == .add && targetScreen != .add {
                prefillAddTitle = nil
                prefillAddDetail = nil
            }
            screen = targetScreen
        }
    }

    func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.toastMessage == message else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.toastMessage = nil
            }
        }
    }
}

/// Today's activity and the derived working-hours figures.
@MainActor
final class TodaySummary: ObservableObject {
    @Published private(set) var sessions: [WorkSession] = []
    @Published private(set) var referenceDate: Date = Date()
    @Published private(set) var attachmentsBySession: [Int64: [Attachment]] = [:]

    private var store: SessionStore?
    private var ticker: Timer?

    private let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    func bind(store: SessionStore) {
        self.store = store
        refresh()

        // One second, not twenty: the primary timer shows a seconds field, so
        // it must be republished every second or the clock visibly stalls.
        // The work is trivial — recomputing `Date()` and the derived figures
        // from an in-memory array costs nothing at this rate.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func refresh() {
        guard let store else { return }
        referenceDate = Date()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? referenceDate
        let fetched = store.sessions(in: DateInterval(start: start, end: end))
        // Newest activities at the very top (running session first, then descending by startedAt)
        sessions = fetched.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning
            }
            return lhs.startedAt > rhs.startedAt
        }
        attachmentsBySession = store.attachments
    }

    /// Total working time today, clipped to the workday.
    var workedSeconds: TimeInterval {
        guard let store else { return 0 }
        return WorkSchedule.totalWorked(on: referenceDate, sessions: store.sessions)
    }

    /// Count of recorded / titled activities today.
    var recordedCount: Int {
        sessions.filter { $0.isReportable || $0.recorded }.count
    }

    /// Raw elapsed time today, unclipped. This is the primary timer: it keeps
    /// running outside office hours and at weekends, because a stopped clock
    /// reads as a broken app. The working-hours figure is the one that gets
    /// reported.
    var rawElapsedSeconds: TimeInterval {
        guard let store else { return 0 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: referenceDate)
        var total: TimeInterval = 0
        for session in store.sessions(in: DateInterval(start: start, end: referenceDate)) {
            let end = session.endedAt ?? referenceDate
            total += max(0, end.timeIntervalSince(session.startedAt))
        }
        return total
    }

    /// True when the clock is inside the 07:30–17:00 window on a workday.
    /// Drives the live dot, so it is obvious at a glance whether the small
    /// "jam kerja" figure is currently accumulating.
    var isWorkingNow: Bool {
        WorkSchedule.isWorkday(referenceDate)
            && WorkSchedule.isWithinWindow(referenceDate)
    }

    func workedSeconds(for session: WorkSession) -> TimeInterval {
        let end = session.endedAt ?? referenceDate
        return WorkSchedule.worked(
            in: DateInterval(start: session.startedAt, end: max(end, session.startedAt))
        )
    }

    func attachmentCount(for session: WorkSession) -> [Attachment] {
        attachmentsBySession[session.id] ?? []
    }

    /// The character's mood tracks the working day: asleep before hours,
    /// thinking during them, satisfied once the target is met.
    var characterEmotion: String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: referenceDate)
        guard (2...6).contains(weekday) else { return "00" }  // weekends: asleep

        let components = calendar.dateComponents([.hour, .minute], from: referenceDate)
        let seconds = Double((components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60)

        if seconds < Double(WorkSchedule.startOfDay) { return "00" }
        if seconds >= Double(WorkSchedule.endOfDay) { return "33" }
        if workedSeconds >= 8 * 3600 { return "33" }
        if WorkSchedule.isWorkday(referenceDate) { return "30" }
        return "02"
    }

    var statusLine: String? {
        if !WorkSchedule.isWorkday(referenceDate) { return "di luar jam kerja" }
        let remaining = max(0, 8 * 3600 - workedSeconds)
        if remaining < 60 { return "target tercapai" }
        return "sisa \(WorkSchedule.label(remaining))"
    }

    func timeLabel(_ date: Date) -> String { clock.string(from: date) }
}

/// Erases a view's concrete type to `AnyView`.
///
/// Used only where a generic parameter has to be pinned so a nested type
/// inside that generic is nameable from the call site. `AnyView` costs one
/// extra render pass, so it belongs at a boundary, not in a hot layout.
extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}

// MARK: - Shared controls

/// Icon + label button used across the expanded panel.
func iconButton(
    _ title: String,
    _ symbol: String,
    prominent: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13.5, weight: .semibold))
            Text(title)
                .font(.system(size: 15, weight: prominent ? .bold : .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(prominent ? Color.white : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(prominent ? Color.clear : Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .foregroundStyle(prominent ? Color.black : Color.white.opacity(0.92))
    }
    .buttonStyle(NotchPressStyle())
}

/// Compact label: icon beside text at small sizes, where the default label
/// spacing eats too much horizontal room in a 460pt panel.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}
