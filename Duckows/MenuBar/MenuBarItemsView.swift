import AppKit
import SwiftUI

/// The mirrored menu bar extras, sitting to the left of the native widgets the
/// way Windows puts third-party notification icons before the system ones.
struct MenuBarItemsView: View {
    @ObservedObject private var registry = MenuBarItemRegistry.shared

    var body: some View {
        HStack(spacing: 0) {
            ForEach(registry.items) { item in
                MenuBarItemButton(item: item)
            }
        }
    }
}

private struct MenuBarItemButton: View {
    let item: MirroredMenuBarItem

    @State private var isHovered = false

    var body: some View {
        Button {
            MenuBarItemRegistry.shared.press(item)
        } label: {
            Group {
                if let icon = AppIconProvider.icon(pid: item.pid,
                                                   bundleIdentifier: item.bundleIdentifier,
                                                   size: 15) {
                    Image(nsImage: icon)
                } else {
                    Image(systemName: "app.dashed")
                }
            }
            .frame(minWidth: 28)
            .frame(maxHeight: .infinity)
            .background(Color.primary.opacity(isHovered ? 0.14 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.appName)
    }
}
