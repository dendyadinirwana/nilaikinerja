import Foundation
import Combine

/// Drives the per-item entrance stagger when the panel expands.
///
/// The rows cannot simply animate on `isExpanded`, because every row would
/// start on the same frame and the list would arrive as one block — which is
/// exactly the "snap" this replaces. Instead each row waits its own slice of
/// the cascade before it is allowed to move.
///
/// The clock is an explicit token rather than a Timer. Bumping `token` is what
/// restarts the cascade, so reopening the panel after a collapse replays the
/// stagger from the top, and a re-render mid-cascade does not reset it.
@MainActor
final class RevealCascade: ObservableObject {
    /// Incremented on every open. Rows key their animation off this value.
    @Published private(set) var token: Int = 0

    /// Seconds between consecutive rows.
    @Published var stagger: Double = 0.05

    /// Delay before a row at `index` begins moving.
    ///
    /// Clamped so a long list cannot produce a cascade the user has already
    /// stopped watching: past the sixth row everything arrives together, which
    /// reads as a settled list rather than a slow trickle.
    func delay(for index: Int) -> Double {
        min(Double(index), 6) * stagger
    }

    /// Restart the cascade. Called when the panel opens.
    func restart() {
        token &+= 1
    }
}
