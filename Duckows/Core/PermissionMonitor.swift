import AppKit
import ApplicationServices

/// Tracks the Accessibility grant, which is what lets Duckows read window
/// titles and (later) move windows.
///
/// There is no reliable notification when the user flips the switch, so while
/// the onboarding window is up the state is polled; the rest of the time a
/// re-check on activation is enough, since granting it means visiting System
/// Settings and coming back.
@MainActor
final class PermissionMonitor: ObservableObject {
    static let shared = PermissionMonitor()

    @Published private(set) var isAccessibilityTrusted = false
    /// Bumped on every refresh, even when nothing changed, so views can react
    /// to "we looked again" rather than only to a value flipping.
    @Published private(set) var refreshCount = 0

    private var pollingTask: Task<Void, Never>?

    private init() {
        refresh()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        let changed = trusted != isAccessibilityTrusted
        isAccessibilityTrusted = trusted
        refreshCount += 1
        if changed {
            NotificationCenter.default.post(name: .duckowsAccessibilityChanged, object: nil)
        }
    }

    /// Asks macOS to show its own Accessibility prompt.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            refresh()
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    @objc private func applicationDidBecomeActive() {
        refresh()
    }
}

extension Notification.Name {
    static let duckowsAccessibilityChanged = Notification.Name("Duckows.accessibilityChanged")
}
