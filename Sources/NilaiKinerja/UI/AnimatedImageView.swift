import SwiftUI
import AppKit

// The collapsed-capsule character, and the vestigial sprite pack behind it.
//
// HISTORY, kept because it is the reason this file is mostly plumbing for
// something nothing draws:
//
// This originally wrapped `NSImageView` and assumed AppKit would step the
// frames of an animated PNG. AppKit does not animate APNG: the resulting
// `NSImage` has representations but no `NSImageAnimatableImagePropertyContainer`,
// so `numberOfFrames` is false and the view renders frame 0 forever. That code
// compiled, looked right in a still, and never moved.
//
// The pack it loaded (`Resources/living-icon/skippy/`, 15 APNGs) was also the
// wrong character entirely — a humanoid naval officer, not this app's mascot —
// and no rendered view ever referenced it.
//
// The character is now drawn by `MochiRenderer.swift`, ported from Coucou.
// `LiveIconPack` still loads the old assets so those 15 files keep resolving in
// the bundle; nothing renders from it. Removing the pack and `APNGSpriteView`
// together is the deliberate follow-up.
@MainActor
final class LiveIconPack: ObservableObject {
    /// Voice states, matching the upstream contract.
    enum Voice: String {
        case idle, listening, talking
    }

    /// Moods. `calm` is the fallback for anything unmapped.
    enum Mood: String {
        case calm, excited, somber, angry, thrilled

        /// The nearest mood for an emotional valence, so an emotion id the pack
        /// has no direct artwork for still renders something appropriate
        /// instead of falling back to flat `calm` for everything.
        static func nearest(to valence: Double) -> Mood {
            switch valence {
            case ..<(-0.5): return .angry
            case ..<(-0.15): return .somber
            case ..<0.15: return .calm
            case ..<0.5: return .excited
            default: return .thrilled
            }
        }
    }

    private var frames: [Voice: [Mood: APNGFrames]] = [:]
    /// `@Published` is load-bearing, not decoration. The pack is filled
    /// *after* the first render — `bind()` runs after the view hierarchy is
    /// built — so the collapsed capsule draws once against an empty dictionary.
    /// A plain stored property gives SwiftUI no reason to redraw, and the
    /// character stays invisible until something unrelated forces a rebuild.
    @Published private(set) var isLoaded = false

    /// Diagnostic summary of what actually decoded. Sprites that silently fall
    /// back to frame zero are indistinguishable from sprites that are missing,
    /// so the count is worth having when the mascot refuses to move.
    @Published private(set) var loadReport: String = ""

    /// Load every mood of every voice state. Missing files are skipped rather
    /// than fatal: a partial pack still animates, it just has fewer moods.
    func load() {
        guard !isLoaded else { return }
        var report: [String] = []

        for voice in [Voice.idle, .listening, .talking] {
            var byMood: [Mood: APNGFrames] = [:]
            for mood in [Mood.calm, .excited, .somber, .angry, .thrilled] {
                let name = "living-icon/skippy/\(voice.rawValue)/\(mood.rawValue).png"
                guard let url = Bundle.main.url(forResource: name, withExtension: ""),
                      let data = try? Data(contentsOf: url) else {
                    report.append("\(voice.rawValue)/\(mood.rawValue)=MISSING")
                    continue
                }
                guard let decoded = APNGFrames.decode(data: data), decoded.count > 1 else {
                    report.append("\(voice.rawValue)/\(mood.rawValue)=STATIC")
                    continue
                }
                byMood[mood] = decoded
                report.append("\(voice.rawValue)/\(mood.rawValue)=\(decoded.count)f")
            }
            if !byMood.isEmpty { frames[voice] = byMood }
        }

        isLoaded = !frames.isEmpty
        loadReport = report.joined(separator: " ")
        NSLog("[Mochi] sprite pack (unused): \(loadReport)")
    }

    /// The animation for a voice/mood pair, degrading voice → idle and then
    /// mood → calm so a missing combination never renders nothing.
    func sprite(voice: Voice, mood: Mood) -> APNGFrames? {
        frames[voice]?[mood]
            ?? frames[.idle]?[mood]
            ?? frames[voice]?[.calm]
            ?? frames[.idle]?[.calm]
    }

    /// Every voice/mood actually present. Used by the sprite-proof demo to
    /// prove each one renders instead of assuming the load succeeded.
    func allCombos() -> [(Voice, Mood)] {
        var result: [(Voice, Mood)] = []
        for voice in [Voice.idle, .listening, .talking] {
            for mood in [Mood.calm, .excited, .somber, .angry, .thrilled] {
                if frames[voice]?[mood] != nil {
                    result.append((voice, mood))
                }
            }
        }
        return result
    }
}

/// Voice state for the mascot, derived from what the panel is actually doing.
///
/// `listening` exists in the pack but is deliberately never selected: there is
/// no microphone feature, so an artwork set that implies the user is being
/// listened to would be a lie about the app's behaviour.
enum MochiVoice {
    /// Working, or just sitting in the capsule.
    case idle
    /// The AI is streaming a reply, or a celebration is running.
    case talking

    var packValue: LiveIconPack.Voice {
        switch self {
        case .idle: return .idle
        case .talking: return .talking
        }
    }
}

struct LiveCharacterView: View {
    /// Mood Mates emotion id, kept so the day-to-mood mapping does not change.
    var emotion: String
    /// Kept for backwards compatibility with call sites.
    @ObservedObject var pack: LiveIconPack
    var pointSize: CGFloat
    var voice: MochiVoice = .idle
    var moodOverride: LiveIconPack.Mood? = nil

    /// Map the mood value onto RobotHeadState vocabulary.
    private var state: RobotHeadState {
        switch moodOverride {
        case .excited, .thrilled: return .working
        case .angry: return .error
        case .somber: return .sleeping
        default:
            return .idle
        }
    }

    var body: some View {
        RobotHeadView(
            state: state,
            shape: .rectangle,
            size: pointSize,
            color: "#2563EB",
            trimColor: "#93A6C8",
            screenColor: "#E8F2FF",
            antenna: false,
            floorShadow: false
        )
        .frame(width: pointSize, height: pointSize)
    }
}
