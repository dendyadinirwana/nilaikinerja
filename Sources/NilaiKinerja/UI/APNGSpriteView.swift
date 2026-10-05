import AppKit
import ImageIO
import SwiftUI

/// Decoded APNG frames with their authored timing.
///
/// ImageIO is the only decoder on the platform that understands APNG. AppKit's
/// `NSImage(data:)` splits the file into representations but does NOT make it
/// an `NSImageAnimatableImagePropertyContainer`, so `NSImageView` renders only
/// frame 0 — the mascot sits perfectly still while the bundle quietly contains
/// fifteen fully animated sprites. Probed and confirmed: ImageIO reports 12–16
/// frames per file, the resulting `NSImage` reports zero animatable frames.
///
/// A class, not a struct: the view layer compares identity to decide whether a
/// mood switch should restart the loop or leave a running animation alone, and
/// two structurally equal frame sets are still two different sprites.
final class APNGFrames {
    let images: [CGImage]
    /// Per-frame duration in seconds, from the APNG frame-control chunks.
    let delays: [Double]

    init(images: [CGImage], delays: [Double]) {
        self.images = images
        self.delays = delays
    }

    var count: Int { images.count }
    var pixelSize: CGSize {
        guard let first = images.first else { return .zero }
        return CGSize(width: first.width, height: first.height)
    }

    var loopDuration: Double { delays.reduce(0, +) }

    /// Decodes every frame eagerly.
    ///
    /// Eager is deliberate: this runs once at launch, and a lazily decoded
    /// animation would put disk I/O and PNG inflate on the hover path — the
    /// exact stall the notch must never have.
    static func decode(data: Data) -> APNGFrames? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var images: [CGImage] = []
        var delays: [Double] = []
        images.reserveCapacity(count)
        delays.reserveCapacity(count)

        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            images.append(frame)

            // Unclamped first: a source that asks for a 0.1s delay is stating
            // intent, and clamping to the APNG 1/100s floor would silently
            // retime the artist's animation.
            var delay: Double = 0.1
            if let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
               let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any],
               let raw = png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double
                ?? png[kCGImagePropertyAPNGDelayTime] as? Double {
                delay = max(0.01, raw)
            }
            delays.append(delay)
        }

        guard !images.isEmpty else { return nil }
        return APNGFrames(images: images, delays: delays)
    }
}

/// Drives an `APNGFrames` and repaints on frame changes.
///
/// The clock is owned here rather than handed to `NSImageView`, because AppKit's
/// animation path is reserved for GIF: a sprite animated through it renders
/// frame zero forever. Owning the tick also means the loop length follows the
/// authored timing (0.84s–1.76s across this pack) instead of an invented
/// constant.
final class APNGPlaybackView: NSView {
    private(set) var frames: APNGFrames?
    private var frameIndex: Int = 0
    /// Exposed for the `--spritedump` diagnostic. "The mascot is in the bundle"
    /// and "the mascot is actually moving" are different claims, and only this
    /// number distinguishes them.
    private(set) var currentFrameIndex: Int = 0
    /// Number of times the view actually repainted. A non-zero count alongside
    /// a moving index is the difference between "timer fired" and "user saw it".
    private(set) var repaintCount: Int = 0
    private var elapsed: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    private var timer: Timer?
    private(set) var isPlaying = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Decoration sitting next to clickable controls: VoiceOver announcing
        // a bouncing mascot would be noise. Note this is the *method*, not the
        // KVC key of the same name — setting the key raises
        // NSUnknownKeyException, which AppKit turns into a SIGTRAP.
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Playback

    func setFrames(_ frames: APNGFrames?) {
        guard self.frames !== frames else { return }
        self.frames = frames
        frameIndex = 0
        elapsed = 0
        needsDisplay = true
    }

    func start() {
        guard !isPlaying, let frames, frames.count > 1 else { return }
        isPlaying = true
        lastTick = ProcessInfo.processInfo.systemUptime

        // 120Hz so a 0.07s authored delay lands on real frames. The artwork is
        // 72px displayed at up to 120pt, so the extra ticks are cheap.
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isPlaying, let frames, frames.count > 1 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let delta = now - lastTick
        lastTick = now
        elapsed += delta

        // Consume whole frames, so a late timer tick advances more than one
        // frame instead of letting the loop drift against the authored timing.
        var advanced = false
        while elapsed >= frames.delays[frameIndex] {
            elapsed -= frames.delays[frameIndex]
            frameIndex = (frameIndex + 1) % frames.count
            advanced = true
        }
        if advanced {
            currentFrameIndex = frameIndex
            needsDisplay = true
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        repaintCount += 1
        guard let frames else { return }
        let image = frames.images[min(frameIndex, frames.count - 1)]
        let rep = NSBitmapImageRep(cgImage: image)

        // Source pixels are square; letterbox into whatever box SwiftUI gave us
        // so the mascot keeps its aspect on a non-square slot.
        let side = min(bounds.width, bounds.height)
        let origin = NSPoint(x: bounds.midX - side / 2, y: bounds.midY - side / 2)

        // isFlipped is true, so drawing in a flipped context keeps the sprite
        // upright without a transform.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        rep.draw(in: NSRect(origin: origin, size: NSSize(width: side, height: side)))
    }
}

/// SwiftUI wrapper for a decoded APNG sprite.
struct APNGSpriteView: NSViewRepresentable {
    let frames: APNGFrames
    var isPlaying: Bool = true

    func makeNSView(context: Context) -> APNGPlaybackView {
        let view = APNGPlaybackView(frame: .zero)
        view.setFrames(frames)
        if isPlaying { view.start() }
        return view
    }

    func updateNSView(_ view: APNGPlaybackView, context: Context) {
        // Identity, not equality: swapping to a different mood must restart the
        // loop from frame 0, while a SwiftUI redraw of the same sprite must not
        // visibly stutter.
        if view.frames !== frames {
            view.setFrames(frames)
        }
        if isPlaying {
            if !view.isPlaying { view.start() }
        } else {
            view.stop()
        }
    }

    static func dismantleNSView(_ view: APNGPlaybackView, coordinator: ()) {
        view.stop()
    }
}