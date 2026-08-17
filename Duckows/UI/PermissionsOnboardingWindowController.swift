import AppKit
import SwiftUI

/// The first-run explanation of why Duckows needs Accessibility.
///
/// Shown only when the permission is missing, and it closes itself the moment
/// the grant lands so the user does not have to come back and dismiss it.
@MainActor
final class PermissionsOnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = PermissionsOnboardingWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func showIfNeeded() {
        guard !PermissionMonitor.shared.isAccessibilityTrusted else { return }
        show()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionsOnboardingView())
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Welcome to Duckows"
            newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            newWindow.titlebarAppearsTransparent = true
            newWindow.isMovableByWindowBackground = true
            newWindow.center()
            newWindow.delegate = self
            newWindow.isReleasedWhenClosed = false
            window = newWindow
        }

        window?.makeKeyAndOrderFront(nil)
        // An agent app cannot take focus without this, and the window would
        // open behind everything.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        PermissionMonitor.shared.startPolling()
    }

    func close() {
        PermissionMonitor.shared.stopPolling()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        PermissionMonitor.shared.stopPolling()
        NSApp.setActivationPolicy(.accessory)
    }
}

struct PermissionsOnboardingView: View {
    @ObservedObject private var permissions = PermissionMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().frame(width: 56, height: 56)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Duckows needs Accessibility")
                        .font(.system(size: 16, weight: .semibold))
                    Text("It is the only way macOS lets an app read window titles.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "What it is used for") {
                Label("Show your open windows by name in the taskbar", systemImage: "textformat")
                    .font(.system(size: 12))
                Label("Bring a window to the front when you click its button", systemImage: "arrow.up.left.square")
                    .font(.system(size: 12))
                Text("Duckows sends nothing anywhere. Its only network request is the update check.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if permissions.isAccessibilityTrusted {
                StatusBanner(style: .success, message: "Accessibility is granted. You are all set.")
            } else {
                StatusBanner(
                    style: .warning,
                    message: "Until this is granted, the taskbar shows your running apps without window titles."
                )
            }

            HStack {
                Button("Open System Settings") {
                    PermissionMonitor.shared.openAccessibilitySettings()
                }
                Spacer()
                Button(permissions.isAccessibilityTrusted ? "Done" : "Grant Access…") {
                    if permissions.isAccessibilityTrusted {
                        PermissionsOnboardingWindowController.shared.close()
                    } else {
                        PermissionMonitor.shared.requestAccessibility()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        // Reacting to the counter rather than the flag means a refresh that
        // confirms the grant still closes the window even if the value was
        // already true by the time this view appeared.
        .onChange(of: permissions.refreshCount) { _, _ in
            if permissions.isAccessibilityTrusted {
                PermissionsOnboardingWindowController.shared.close()
            }
        }
    }
}
