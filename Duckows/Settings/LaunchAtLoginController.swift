import AppKit
import Foundation
import ServiceManagement

/// A `SMAppService` failure, translated into something worth showing a user.
struct LaunchAtLoginError: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isRecoverable: Bool

    // Codes from SMErrors.h. They are matched numerically on purpose:
    // `SMAppServiceErrorDomain` only exists on macOS 15+, and the deployment
    // target here is 14.0.
    init(error: NSError, wasEnabling: Bool) {
        switch error.code {
        case 12: // kSMErrorAlreadyRegistered
            message = "Duckows is already set to open at login."
            isRecoverable = true
        case 6: // kSMErrorJobNotFound
            message = wasEnabling
                ? "macOS could not find the Duckows login item."
                : "Duckows was already removed from login items."
            isRecoverable = true
        case 11: // kSMErrorLaunchDeniedByUser
            message = "macOS blocked the login item. Enable Duckows under Login Items."
            isRecoverable = true
        case 3: // kSMErrorInvalidSignature
            message = "macOS will not open Duckows at login from its current location. "
                + "Move Duckows to your Applications folder and try again."
            isRecoverable = false
        case 1:
            message = "macOS refused the request. Move Duckows to Applications and try again."
            isRecoverable = true
        default:
            message = error.localizedDescription
            isRecoverable = true
        }
    }

    static func == (lhs: LaunchAtLoginError, rhs: LaunchAtLoginError) -> Bool {
        lhs.message == rhs.message && lhs.isRecoverable == rhs.isRecoverable
    }
}

/// Wraps `SMAppService.mainApp`.
///
/// The system is the single source of truth: the user can turn the login item
/// off in System Settings at any time, so the state is never mirrored into
/// `config.json` — it is read back from `status` instead.
@MainActor
final class LaunchAtLoginController: ObservableObject {
    static let shared = LaunchAtLoginController()

    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var lastError: LaunchAtLoginError?

    private init() {
        refresh()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    var isEnabled: Bool { status == .enabled }

    /// Registered, but switched off by the user in Login Items. Only System
    /// Settings can undo that.
    var needsUserApproval: Bool { status == .requiresApproval }

    /// An app launched from a quarantined location runs from a randomised
    /// read-only path, and `register()` fails with an invalid-signature error
    /// that reads as a code-signing bug. Detect it up front instead.
    var isTranslocated: Bool {
        Bundle.main.bundleURL.path.contains("/AppTranslocation/")
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch let error as NSError {
            lastError = LaunchAtLoginError(error: error, wasEnabling: enabled)
            NSLog("Duckows: launch-at-login \(enabled ? "register" : "unregister") failed – \(error)")
        }

        // Registration completes asynchronously inside launchd, so the status
        // read immediately after the call can still be stale.
        refresh()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            refresh()
        }
    }

    /// Re-asserts registration after an in-place update moved the bundle.
    func reconcileAtLaunch(enabledPreference: Bool) {
        guard enabledPreference else { return }
        switch status {
        case .enabled, .requiresApproval:
            break
        case .notRegistered, .notFound:
            try? SMAppService.mainApp.register()
            refresh()
        @unknown default:
            break
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func applicationDidBecomeActive() {
        refresh()
    }
}
