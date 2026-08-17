import AppKit
import SwiftUI

/// One taskbar button: the owning app's icon, and the window's title when
/// there is room for it.
struct TaskbarButtonView: View {
    let item: TaskbarItem
    let taskbar: TaskbarSettings
    let screenUUID: String?
    let width: CGFloat
    let showsTitle: Bool

    @State private var isHovered = false

    private var icon: NSImage? {
        AppIconProvider.icon(
            pid: item.pid,
            bundleIdentifier: item.bundleIdentifier,
            size: taskbar.iconSize
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: taskbar.iconSize, height: taskbar.iconSize)
                    // A minimized window still deserves a button, just a
                    // quieter one.
                    // Only an app with nothing open is dimmed. A minimized
                    // window is still a window you have; it looks exactly like
                    // an open one, and the missing underline is what tells you
                    // it is not the one in front.
                    .opacity(item.hasWindows ? 1 : 0.5)
            }

            if showsTitle {
                Text(item.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(item.hasWindows ? .primary : .secondary)
            }

            // Grouped buttons say how many windows they stand for.
            if showsTitle, taskbar.grouping == .byApp, item.windowIDs.count > 1 {
                Text("\(item.windowIDs.count)")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background {
                        Capsule().fill(Color.primary.opacity(0.14))
                    }
            }
        }
        .padding(.horizontal, showsTitle ? 10 : 0)
        .frame(width: width, height: taskbar.iconSize * 1.25)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
        }
        .overlay(alignment: .bottom) {
            if item.isActive {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            } else if !item.hasWindows {
                // The Dock's running-app dot: alive, but nothing open.
                Circle()
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: 3, height: 3)
                    .padding(.bottom, 2)
            }
        }
        .contentShape(Rectangle())
        .overlay(TaskbarButtonHost(item: item, screenUUID: screenUUID))
        .onHover { isHovered = $0 }
        .help(item.title)
    }

    private var background: Color {
        if item.isActive { return Color.primary.opacity(0.16) }
        if isHovered { return Color.primary.opacity(0.11) }
        return Color.primary.opacity(0.06)
    }
}

/// Shown instead of window buttons when Accessibility has not been granted.
struct GrantAccessChip: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            PermissionsOnboardingWindowController.shared.show()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").font(.system(size: 11))
                Text("Grant Accessibility").font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background {
                Capsule().fill(Color.orange.opacity(isHovered ? 0.34 : 0.22))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Duckows needs Accessibility to show window titles")
    }
}
