import AppKit
import SwiftUI

/// The chevron at the end of a full bar, holding the buttons that did not fit.
struct OverflowButton: View {
    let items: [TaskbarItem]
    let height: CGFloat

    var body: some View {
        OverflowHost(items: items)
            .frame(width: StripLayout.overflowButtonWidth, height: height)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            }
            .overlay {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .allowsHitTesting(false)
            }
            .help("\(items.count) more")
    }
}

/// AppKit again, for the same reason the buttons are: the bar is a
/// non-activating panel, and `NSMenu.popUp` opens from one without making
/// Duckows the active application.
private struct OverflowHost: NSViewRepresentable {
    let items: [TaskbarItem]

    func makeNSView(context: Context) -> Catcher {
        let view = Catcher()
        view.items = items
        return view
    }

    func updateNSView(_ view: Catcher, context: Context) {
        view.items = items
    }

    final class Catcher: NSView {
        var items: [TaskbarItem] = []

        override func mouseDown(with event: NSEvent) {
            MainActor.assumeIsolated { showMenu() }
        }

        override func rightMouseDown(with event: NSEvent) {
            MainActor.assumeIsolated { showMenu() }
        }

        @MainActor
        private func showMenu() {
            let menu = NSMenu()
            for item in items {
                let entry = NSMenuItem(
                    title: item.title,
                    action: #selector(MenuTarget.activateItem(_:)),
                    keyEquivalent: ""
                )
                entry.target = MenuTarget.shared
                entry.representedObject = item.id
                entry.image = AppIconProvider.icon(
                    pid: item.pid, bundleIdentifier: item.bundleIdentifier, size: 16
                )
                // Dimmed the same way the button would have been.
                entry.state = item.hasWindows && !item.isHidden ? .off : .mixed
                menu.addItem(entry)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
        }
    }
}
