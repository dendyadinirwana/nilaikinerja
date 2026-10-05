import SwiftUI
import AppKit
import WebKit

/// Hosts the Mood Mates character engine in a `WKWebView`.
///
/// The upstream project (github.com/sam70361/aora-bot, `mood-mates/`) is
/// zero-dependency vanilla JS that renders a character as SVG from parametric
/// geometry — there are no hand-drawn coordinates anywhere in the engine.
/// Reimplementing that in SwiftUI would mean porting ~3,800 lines of animation
/// code for no benefit, so the engine is bundled as-is and driven from a small
/// HTML shim loaded out of the app bundle.
///
/// The web view is deliberately inert: no navigation delegate is installed, so
/// the page cannot navigate away or reach the network, and the configuration
/// uses a non-persistent data store so nothing is written to disk.
///
/// Licence: Mood Mates is non-commercial — see `Resources/mood-mates/LICENSE`.
/// The character artwork must not be used commercially. This integration is
/// for personal use.
struct CharacterView: NSViewRepresentable {
    typealias NSViewType = WKWebView

    /// Emotion id, per the upstream contract: 00–09 lifecycle, 10–29 emotion,
    /// 30–49 agent work state, 50+ custom.
    var emotion: String
    var character: String
    /// Rendering stops when the panel is collapsed or off-screen, so the
    /// animation costs nothing while the user is not looking.
    var isActive: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        config.websiteDataStore = .nonPersistent()

        let webView = PassThroughWebView(frame: .zero, configuration: config)
        // macOS WKWebView has no `isOpaque`/`backgroundColor`. The supported
        // way to make the page see-through is `underPageBackgroundColor`;
        // the page's own CSS also sets a transparent background.
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        // The character is decoration, so it must not be announced by
        // VoiceOver. Set through the public accessibility API rather than a
        // KVC key: a key that does not exist raises `NSUnknownKeyException`,
        // which AppKit converts into a SIGTRAP whose crash log records no
        // reason at all.
        webView.setAccessibilityElement(false)
        webView.setAccessibilityRole(.unknown)

        if let url = Bundle.main.url(forResource: "character", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // The page may not have finished loading yet; `window.nilaiMate` is
        // undefined until it does. Re-issuing on every SwiftUI update means a
        // missed call is simply retried on the next one, with no handshake to
        // get wrong.
        guard emotion != context.coordinator.lastEmotion else {
            setActive(webView, isActive)
            return
        }
        context.coordinator.lastEmotion = emotion
        setActive(webView, isActive)
        call(webView, "window.nilaiMate && window.nilaiMate.setEmotion('\(emotion)')")
    }

    private func setActive(_ webView: WKWebView, _ active: Bool) {
        call(webView, "window.nilaiMate && window.nilaiMate.setActive(\(active ? "true" : "false"))")
    }

    private func call(_ webView: WKWebView, _ script: String) {
        webView.evaluateJavaScript(script) { _, error in
            // A missing bridge before the page loads is expected and retried on
            // the next update, so it is not worth logging. A JavaScript
            // exception inside the engine itself is worth surfacing.
            guard let error else { return }
            let ns = error as NSError
            let isMissingBridge = ns.domain == "WKJavaScriptExceptionDomain"
                && ns.code == 3  // "undefined is not an object"
            if !isMissingBridge {
                NSLog("[Character] \(ns.localizedDescription)")
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastEmotion: String = ""
    }
}

/// A `WKWebView` that never claims a mouse event.
///
/// The character is decoration. Without this, the web view's scroll view
/// swallows clicks and drags over the panel, which would break the activity
/// list and the file drop zone behind it. Overriding `hitTest` is preferred
/// over the `mouseTransparent` KVC key, which is undocumented and would raise
/// an `NSUnknownKeyException` on a WebKit version that lacks it.
final class PassThroughWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
