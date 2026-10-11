import Foundation
import AppKit
import UserNotifications
import ApplicationServices

/// Manages macOS system permissions required for NilaiKinerja.
///
/// Permissions managed:
/// 1. Accessibility (Aksesibilitas):
///    Required for global event monitoring (`NSEvent.addGlobalMonitorForEvents`)
///    to detect mouse location and drag & drop operations when other apps are active.
/// 2. User Notifications (Pemberitahuan Sistem):
///    Required for periodic ASN checkpoint reminders and task alerts.
@MainActor
final class SystemPermissionManager: ObservableObject {
    static let shared = SystemPermissionManager()

    private let defaults = UserDefaults.standard
    private let promptedKey = "settings.hasPromptedSystemPermissions"

    @Published var isAccessibilityGranted: Bool = false
    @Published var isNotificationGranted: Bool = false

    init() {
        checkStatus()
    }

    /// Checks the current authorization status without triggering prompts.
    func checkStatus() {
        // 1. Accessibility check without prompt
        isAccessibilityGranted = AXIsProcessTrusted()

        // 2. Notifications status
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                Task { @MainActor in
                    self.isNotificationGranted = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
                }
            }
        }
    }

    /// Automatically triggers permission requests on first launch.
    func requestPermissionsOnFirstLaunchIfNeeded() {
        let hasPrompted = defaults.bool(forKey: promptedKey)
        guard !hasPrompted else {
            // Still check status silently on subsequent launches
            checkStatus()
            return
        }

        defaults.set(true, forKey: promptedKey)
        NKLog("[Permission] First launch detected — requesting all required macOS permissions...")

        // Small delay to allow the notch window to finish anchoring before showing system dialogs
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.requestAllPermissions()
        }
    }

    /// Triggers both Accessibility and Notification prompts.
    func requestAllPermissions() {
        requestAccessibilityPermission()
        requestNotificationPermission()
    }

    /// Prompts the macOS Accessibility system dialog.
    func requestAccessibilityPermission() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let trusted = AXIsProcessTrustedWithOptions(options)
        self.isAccessibilityGranted = trusted
        NKLog("[Permission] Accessibility trusted=\(trusted)")
    }

    /// Prompts the macOS User Notifications system dialog.
    func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            Task { @MainActor in
                self.isNotificationGranted = granted
                if let error {
                    NKLog("[Permission] Notification error: \(error.localizedDescription)")
                } else {
                    NKLog("[Permission] Notification granted=\(granted)")
                }
            }
        }
    }

    /// Opens macOS System Settings directly to Privacy & Security -> Accessibility.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens macOS System Settings directly to Notifications.
    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}
