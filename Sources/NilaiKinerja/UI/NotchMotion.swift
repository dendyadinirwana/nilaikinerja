import SwiftUI

/// Transient motion state for the notch surface.
///
/// The collapsed capsule breathes slightly on hover. This is an `ObservableObject`
/// rather than `@State` because `@State` is a compiler macro in Swift 6 whose
/// plugin ships only with Xcode — see the skill `macos-notch-app-without-xcode`.
@MainActor
final class NotchMotion: ObservableObject {
    /// Scale applied to the collapsed capsule. 1.0 at rest, slightly larger
    /// while hovered.
    @Published private(set) var hoverScale: CGFloat = 1.0

    private var restTask: DispatchWorkItem?

    func setHovering(_ hovering: Bool) {
        restTask?.cancel()
        restTask = nil
        hoverScale = 1.0
    }
}

/// Press feedback for the small panel buttons.
struct NotchPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Form state lives in an observable object rather than `@State`.
///
/// `@State` is a compiler macro in Swift 6, and its implementation plugin
/// ships only with the full Xcode toolchain — not with Command Line Tools.
/// Keeping the form state in an `ObservableObject` (whose `@Published` is an
/// ordinary property wrapper) is what lets this app build with `swift build`
/// alone. Same behaviour, no macro dependency.
@MainActor
final class CheckpointForm: ObservableObject {
    @Published var title: String = ""
    @Published var detail: String = ""
    @Published var outcome: String = ""

    /// Cleared on collapse so the next checkpoint does not inherit stale text.
    func reset(from session: WorkSession?) {
        title = session?.title ?? ""
        detail = session?.detail ?? ""
        outcome = session?.outcome ?? ""
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var optionalDetail: String? { detail.isEmpty ? nil : detail }
    var optionalOutcome: String? { outcome.isEmpty ? nil : outcome }
}
