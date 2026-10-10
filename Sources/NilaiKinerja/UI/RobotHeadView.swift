import SwiftUI
import AppKit
import WebKit

/// The animated 3D TV-headed bot from fayazara/robot-heads.
///
/// Permissive MIT License (Copyright (c) 2026 Fayaz Ahmed).
/// Replaces the Mochi character port so NilaiKinerja is fully open and 100%
/// redistributable without character asset restrictions.
enum RobotHeadState: String, CaseIterable {
    case idle
    case thinking
    case searching
    case listening
    case speaking
    case working
    case happy
    case error
    case sleeping
}

enum RobotHeadShape: String, CaseIterable {
    case rectangle
    case square
    case circle
    case hexagon
}

struct RobotHeadView: NSViewRepresentable {
    typealias NSViewType = WKWebView

    var state: RobotHeadState = .idle
    var shape: RobotHeadShape = .rectangle
    var size: CGFloat = 130
    var color: String = "#2563EB"
    var trimColor: String = "#93A6C8"
    var screenColor: String = "#E8F2FF"
    var antenna: Bool = true
    var floorShadow: Bool = true
    var speed: Double = 1.0
    var pokeTrigger: Int = 0

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        config.websiteDataStore = .nonPersistent()

        let webView = PassThroughWebView(frame: .zero, configuration: config)
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.setAccessibilityElement(false)
        webView.setAccessibilityRole(.unknown)

        loadURL(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastState != state {
            context.coordinator.lastState = state
            call(webView, "window.robotBridge && window.robotBridge.setState('\(state.rawValue)')")
        }
        if context.coordinator.lastShape != shape {
            context.coordinator.lastShape = shape
            call(webView, "window.robotBridge && window.robotBridge.setShape('\(shape.rawValue)')")
        }
        if context.coordinator.lastPokeTrigger != pokeTrigger {
            context.coordinator.lastPokeTrigger = pokeTrigger
            call(webView, "window.robotBridge && window.robotBridge.poke()")
        }
    }

    private func loadURL(webView: WKWebView) {
        guard let baseURL = Bundle.main.url(forResource: "robot", withExtension: "html", subdirectory: "robot-heads")
                ?? Bundle.main.url(forResource: "robot", withExtension: "html") else {
            return
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "size", value: "\(Int(size))"),
            URLQueryItem(name: "shape", value: shape.rawValue),
            URLQueryItem(name: "state", value: state.rawValue),
            URLQueryItem(name: "color", value: color),
            URLQueryItem(name: "trimColor", value: trimColor),
            URLQueryItem(name: "screenColor", value: screenColor),
            URLQueryItem(name: "antenna", value: antenna ? "1" : "0"),
            URLQueryItem(name: "floorShadow", value: floorShadow ? "1" : "0"),
            URLQueryItem(name: "speed", value: "\(speed)"),
            URLQueryItem(name: "interactive", value: "1")
        ]

        if let finalURL = components?.url {
            webView.loadFileURL(finalURL, allowingReadAccessTo: finalURL.deletingLastPathComponent())
        }
    }

    private func call(_ webView: WKWebView, _ script: String) {
        webView.evaluateJavaScript(script) { _, _ in }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastState: RobotHeadState?
        var lastShape: RobotHeadShape?
        var lastPokeTrigger: Int = 0
    }
}
