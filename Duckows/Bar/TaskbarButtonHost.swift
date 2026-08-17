import AppKit
import SwiftUI

/// Handles clicks on a taskbar button.
///
/// This is AppKit rather than SwiftUI's `Button` and `.contextMenu` because the
/// bar is a `.nonactivatingPanel`: `.contextMenu` wants a key window and does
/// not reliably open from one, while `NSMenu.popUp` runs its own event loop and
/// works without ever activating Duckows — which is the whole point, since a
/// click here is meant to activate the *target* app.
struct TaskbarButtonHost: NSViewRepresentable {
    let item: TaskbarItem

    func makeNSView(context: Context) -> ClickCatcher {
        let view = ClickCatcher()
        view.item = item
        return view
    }

    func updateNSView(_ view: ClickCatcher, context: Context) {
        view.item = item
    }

    final class ClickCatcher: NSView {
        var item: TaskbarItem?

        override func mouseDown(with event: NSEvent) {
            guard let item else { return }
            MainActor.assumeIsolated {
                let records = WindowRegistry.shared.records(for: item)
                let isFrontmost = WindowRegistry.shared.frontmostApplication == item.pid

                if let record = records.first, records.count == 1 {
                    WindowActions.toggle(record, isFrontmost: isFrontmost)
                } else if records.isEmpty {
                    // The degraded, no-Accessibility bar has no window records.
                    NSRunningApplication(processIdentifier: item.pid)?.activate()
                } else if isFrontmost {
                    WindowActions.hide(pid: item.pid)
                } else {
                    records.forEach(WindowActions.raise)
                }
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let item else { return }
            MainActor.assumeIsolated {
                let menu = Self.makeMenu(for: item)
                menu.popUp(positioning: nil,
                           at: NSPoint(x: 0, y: bounds.height + 4),
                           in: self)
            }
        }

        @MainActor
        private static func makeMenu(for item: TaskbarItem) -> NSMenu {
            let menu = NSMenu()
            let records = WindowRegistry.shared.records(for: item)

            // A grouped button stands for several windows, so name them.
            if records.count > 1 {
                for record in records {
                    let entry = NSMenuItem(
                        title: record.title,
                        action: #selector(MenuTarget.raiseWindow(_:)),
                        keyEquivalent: ""
                    )
                    entry.target = MenuTarget.shared
                    entry.representedObject = record.id
                    entry.state = record.isMinimized ? .mixed : .off
                    menu.addItem(entry)
                }
                menu.addItem(.separator())
            }

            if let record = records.first, records.count == 1 {
                let minimize = NSMenuItem(
                    title: record.isMinimized ? "Restore" : "Minimize",
                    action: #selector(MenuTarget.toggleMinimize(_:)),
                    keyEquivalent: ""
                )
                minimize.target = MenuTarget.shared
                minimize.representedObject = record.id
                menu.addItem(minimize)

                let close = NSMenuItem(
                    title: "Close Window",
                    action: #selector(MenuTarget.closeWindow(_:)),
                    keyEquivalent: ""
                )
                close.target = MenuTarget.shared
                close.representedObject = record.id
                menu.addItem(close)
                menu.addItem(.separator())
            }

            let quit = NSMenuItem(
                title: "Quit \(NSRunningApplication(processIdentifier: item.pid)?.localizedName ?? "App")",
                action: #selector(MenuTarget.quitApp(_:)),
                keyEquivalent: ""
            )
            quit.target = MenuTarget.shared
            quit.representedObject = NSNumber(value: item.pid)
            menu.addItem(quit)

            return menu
        }
    }
}

/// `NSMenuItem` needs an Objective-C target, which a SwiftUI view cannot be.
@MainActor
final class MenuTarget: NSObject {
    static let shared = MenuTarget()

    private override init() { super.init() }

    private func record(from sender: NSMenuItem) -> WindowRecord? {
        guard let id = sender.representedObject as? CGWindowID else { return nil }
        return WindowRegistry.shared.records(withID: id)
    }

    @objc func raiseWindow(_ sender: NSMenuItem) {
        guard let record = record(from: sender) else { return }
        WindowActions.raise(record)
    }

    @objc func toggleMinimize(_ sender: NSMenuItem) {
        guard let record = record(from: sender) else { return }
        if record.isMinimized {
            WindowActions.raise(record)
        } else {
            WindowActions.minimize(record)
        }
    }

    @objc func closeWindow(_ sender: NSMenuItem) {
        guard let record = record(from: sender) else { return }
        WindowActions.close(record)
    }

    @objc func quitApp(_ sender: NSMenuItem) {
        guard let pid = (sender.representedObject as? NSNumber)?.int32Value else { return }
        WindowActions.quit(pid: pid)
    }
}
