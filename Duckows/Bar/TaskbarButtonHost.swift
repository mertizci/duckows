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
    /// The display this button's bar lives on, so a reopened app lands
    /// where it was asked from rather than where it happened to be last.
    let screenUUID: String?

    func makeNSView(context: Context) -> ClickCatcher {
        let view = ClickCatcher()
        view.item = item
        view.screenUUID = screenUUID
        return view
    }

    func updateNSView(_ view: ClickCatcher, context: Context) {
        view.item = item
        view.screenUUID = screenUUID
    }

    final class ClickCatcher: NSView {
        var item: TaskbarItem?
        var screenUUID: String?

        override func mouseDown(with event: NSEvent) {
            guard let item else { return }
            MainActor.assumeIsolated {
                let records = WindowRegistry.shared.records(for: item)
                let isFrontmost = WindowRegistry.shared.frontmostApplication == item.pid

                if let record = records.first, records.count == 1 {
                    WindowActions.toggle(record, isFrontmost: isFrontmost)
                } else if records.isEmpty {
                    Self.reopen(pid: item.pid, onScreen: self.screenUUID)
                } else {
                    // A grouped button stands for several windows, and guessing
                    // which one you meant is worse than asking. Windows shows
                    // thumbnails here; this shows their titles.
                    self.popUp(Self.windowPicker(for: records))
                }
            }
        }

        /// Brings back an app that is running with nothing open.
        ///
        /// `activate()` only moves focus to an app that has no windows, which
        /// looks like nothing happened. Asking LaunchServices to open it again
        /// sends the reopen event — the same one a Dock tile click sends, and
        /// the thing that actually makes an app put a window back on screen.
        @MainActor
        static func reopen(pid: pid_t, onScreen uuid: String?) {
            guard let app = NSRunningApplication(processIdentifier: pid) else { return }
            // Not app.bundleURL: it is not always a .app, and LaunchServices
            // answers a non-app bundle by opening a Finder window on it.
            guard let url = WindowActions.applicationURL(pid: pid) else {
                app.activate()
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    NSLog("Duckows: could not reopen \(app.localizedName ?? "app") – \(error.localizedDescription)")
                    return
                }
                guard let uuid else { return }
                Task { @MainActor in
                    WindowPlacement.follow(bundleIdentifier: nil, pid: pid, onScreen: uuid)
                }
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let item else { return }
            MainActor.assumeIsolated {
                self.popUp(Self.makeMenu(for: item))
            }
        }

        /// Opens a menu off the top edge of the button.
        ///
        /// With the bar at the bottom of the screen there is no room below, so
        /// AppKit flips the menu upward on its own; anchoring to the top edge is
        /// what makes it land against the button either way.
        @MainActor
        private func popUp(_ menu: NSMenu) {
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: bounds.height + 4),
                       in: self)
        }

        @MainActor
        private static func windowPicker(for records: [WindowRecord]) -> NSMenu {
            let menu = NSMenu()
            for record in records {
                let entry = menuItem(record.title, #selector(MenuTarget.raiseWindow(_:)), record.id)
                entry.image = AppIconProvider.icon(
                    pid: record.pid, bundleIdentifier: record.bundleIdentifier, size: 16
                )
                entry.state = record.isVisible ? .off : .mixed
                menu.addItem(entry)
            }
            return menu
        }

        @MainActor
        private static func makeMenu(for item: TaskbarItem) -> NSMenu {
            let menu = NSMenu()
            let records = WindowRegistry.shared.records(for: item)
            let appName = NSRunningApplication(processIdentifier: item.pid)?.localizedName ?? "App"

            // A grouped button stands for several windows, so name them first.
            if records.count > 1 {
                for record in records {
                    let entry = menuItem(record.title, #selector(MenuTarget.raiseWindow(_:)), record.id)
                    entry.state = record.isMinimized ? .mixed : .off
                    menu.addItem(entry)
                }
                menu.addItem(.separator())
            }

            if let record = records.first, records.count == 1 {
                menu.addItem(menuItem(record.isMinimized ? "Restore" : "Minimize",
                                  #selector(MenuTarget.toggleMinimize(_:)), record.id))
                menu.addItem(menuItem("Maximize", #selector(MenuTarget.maximizeWindow(_:)), record.id))

                // Windows has Win-Shift-Arrow for this; on a multi-monitor desk
                // it is the thing a taskbar is asked for most.
                let others = NSScreen.screens.filter {
                    ScreenIdentity(screen: $0)?.uuid != record.screenUUID
                }
                if !others.isEmpty {
                    let moveItem = NSMenuItem(title: "Move to Display", action: nil, keyEquivalent: "")
                    let submenu = NSMenu()
                    for screen in others {
                        guard let uuid = ScreenIdentity(screen: screen)?.uuid else { continue }
                        let entry = NSMenuItem(title: screen.localizedName,
                                               action: #selector(MenuTarget.moveWindow(_:)),
                                               keyEquivalent: "")
                        entry.target = MenuTarget.shared
                        entry.representedObject = MenuTarget.MoveRequest(windowID: record.id, screenUUID: uuid)
                        submenu.addItem(entry)
                    }
                    moveItem.submenu = submenu
                    menu.addItem(moveItem)
                }

                menu.addItem(.separator())
                menu.addItem(menuItem("Close Window", #selector(MenuTarget.closeWindow(_:)), record.id))
                menu.addItem(.separator())
            }

            // The label is the user's, so renaming belongs to the button rather
            // than to the window or the app.
            menu.addItem(menuItem("Rename…", #selector(MenuTarget.rename(_:)), item.id))
            if CustomNames.shared.name(for: item.id) != nil {
                menu.addItem(menuItem("Reset Name", #selector(MenuTarget.resetName(_:)), item.id))
            }
            menu.addItem(.separator())

            menu.addItem(pidItem("New Window", #selector(MenuTarget.newWindow(_:)), item.pid))
            if NSRunningApplication(processIdentifier: item.pid)?.isHidden == true {
                menu.addItem(pidItem("Show", #selector(MenuTarget.unhideApp(_:)), item.pid))
            } else {
                menu.addItem(pidItem("Hide", #selector(MenuTarget.hideApp(_:)), item.pid))
            }
            menu.addItem(pidItem("Show in Finder", #selector(MenuTarget.revealApp(_:)), item.pid))
            menu.addItem(.separator())

            menu.addItem(pidItem("Quit \(appName)", #selector(MenuTarget.quitApp(_:)), item.pid))
            let force = pidItem("Force Quit \(appName)", #selector(MenuTarget.forceQuitApp(_:)), item.pid)
            // Hidden behind Option, the way the Dock hides it, so it is never a
            // slip of the mouse away.
            force.isAlternate = true
            force.keyEquivalentModifierMask = .option
            menu.addItem(force)

            return menu
        }

        @MainActor
        private static func menuItem(_ title: String, _ action: Selector, _ represented: Any) -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = MenuTarget.shared
            entry.representedObject = represented
            return entry
        }

        @MainActor
        private static func pidItem(_ title: String, _ action: Selector, _ pid: pid_t) -> NSMenuItem {
            menuItem(title, action, NSNumber(value: pid))
        }
    }
}

/// `NSMenuItem` needs an Objective-C target, which a SwiftUI view cannot be.
@MainActor
final class MenuTarget: NSObject {
    static let shared = MenuTarget()

    /// Two values for one menu item, since `representedObject` is a single slot.
    final class MoveRequest: NSObject {
        let windowID: CGWindowID
        let screenUUID: String

        init(windowID: CGWindowID, screenUUID: String) {
            self.windowID = windowID
            self.screenUUID = screenUUID
        }
    }

    private override init() { super.init() }

    private func record(from sender: NSMenuItem) -> WindowRecord? {
        guard let id = sender.representedObject as? CGWindowID else { return nil }
        return WindowRegistry.shared.records(withID: id)
    }

    private func pid(from sender: NSMenuItem) -> pid_t? {
        (sender.representedObject as? NSNumber)?.int32Value
    }

    // MARK: - Window

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

    @objc func maximizeWindow(_ sender: NSMenuItem) {
        guard let record = record(from: sender) else { return }
        WindowActions.maximize(record)
    }

    @objc func moveWindow(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? MoveRequest,
              let record = WindowRegistry.shared.records(withID: request.windowID),
              let screen = NSScreen.screens.first(where: {
                  ScreenIdentity(screen: $0)?.uuid == request.screenUUID
              }) else { return }
        WindowActions.move(record, toScreen: screen)
        WindowActions.raise(record)
    }

    @objc func closeWindow(_ sender: NSMenuItem) {
        guard let record = record(from: sender) else { return }
        WindowActions.close(record)
    }

    // MARK: - Label

    @objc func rename(_ sender: NSMenuItem) {
        guard let itemID = sender.representedObject as? String,
              let current = WindowRegistry.shared.items.first(where: { $0.id == itemID })
        else { return }
        CustomNames.shared.promptToRename(itemID: itemID, currentTitle: current.title)
    }

    @objc func resetName(_ sender: NSMenuItem) {
        guard let itemID = sender.representedObject as? String else { return }
        CustomNames.shared.reset(itemID)
    }

    /// Clicking an entry in the overflow list behaves like clicking the
    /// button it stands for.
    @objc func activateItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let item = WindowRegistry.shared.items.first(where: { $0.id == id }) else { return }
        let records = WindowRegistry.shared.records(for: item)
        if let record = records.first, records.count == 1 {
            WindowActions.toggle(record, isFrontmost: WindowRegistry.shared.frontmostApplication == item.pid)
        } else if records.isEmpty {
            TaskbarButtonHost.ClickCatcher.reopen(pid: item.pid, onScreen: nil)
        } else {
            records.forEach(WindowActions.raise)
        }
    }

    // MARK: - App

    @objc func newWindow(_ sender: NSMenuItem) {
        guard let pid = pid(from: sender) else { return }
        TaskbarButtonHost.ClickCatcher.reopen(pid: pid, onScreen: nil)
    }

    @objc func hideApp(_ sender: NSMenuItem) {
        guard let pid = pid(from: sender) else { return }
        WindowActions.hide(pid: pid)
    }

    @objc func unhideApp(_ sender: NSMenuItem) {
        guard let pid = pid(from: sender) else { return }
        NSRunningApplication(processIdentifier: pid)?.unhide()
    }

    @objc func revealApp(_ sender: NSMenuItem) {
        guard let pid = pid(from: sender) else { return }
        WindowActions.revealInFinder(pid: pid)
    }

    @objc func quitApp(_ sender: NSMenuItem) {
        guard let pid = pid(from: sender) else { return }
        WindowActions.quit(pid: pid)
    }

    @objc func forceQuitApp(_ sender: NSMenuItem) {
        guard let pid = pid(from: sender) else { return }
        WindowActions.forceQuit(pid: pid)
    }
}
