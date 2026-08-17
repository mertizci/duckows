import AppKit
import SwiftUI

/// The bar's visuals, with every input passed in rather than read from the
/// store.
///
/// The settings live preview renders this exact type with a draft copy of the
/// settings, which is what keeps the preview from drifting away from the real
/// bar as the design changes.
struct TaskbarChrome: View {
    let appearance: AppearanceSettings
    let taskbar: TaskbarSettings
    /// Real window buttons, in display-order groups the bar separates.
    /// The settings preview leaves this empty and passes `sampleItems`.
    var itemGroups: [[TaskbarItem]] = []
    var needsAccessibility = false
    /// Stand-ins used only by the settings preview.
    var sampleItems: [SampleItem] = []
    var tray: TraySettings = .default
    var showsClock = true
    var screenUUID: String?

    struct SampleItem: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        var isActive = false
    }

    var body: some View {
        HStack(spacing: 8) {
            StartButton(iconSize: taskbar.iconSize, screenUUID: screenUUID)

            if appearance.showsSeparator {
                BarSeparator(height: taskbar.iconSize * 0.9)
            }

            if needsAccessibility {
                GrantAccessChip()
            }

            GeometryReader { geo in
                strip(available: geo.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            if showsClock {
                TrayView(tray: tray, iconSize: taskbar.iconSize)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BarBackground(appearance: appearance))
    }
}

extension TaskbarChrome {
    /// The first group with anything in it, so separators only ever land
    /// between sections.
    fileprivate func firstShownGroupIndex(visible: [TaskbarItem]) -> Int {
        let ids = Set(visible.map(\.id))
        return itemGroups.firstIndex { group in group.contains { ids.contains($0.id) } } ?? 0
    }

    /// All the buttons, sized to whatever room is left.
    @ViewBuilder
    fileprivate func strip(available: CGFloat) -> some View {
        let flat = itemGroups.flatMap { $0 }
        let layout = StripLayout.compute(
            available: available,
            itemCount: flat.count,
            dividerCount: max(0, itemGroups.count - 1),
            iconSize: taskbar.iconSize,
            maximumButtonWidth: taskbar.maxButtonWidth,
            prefersTitles: taskbar.showsWindowTitles
        )
        let visible = Array(flat.prefix(layout.visibleCount))
        let overflow = Array(flat.dropFirst(layout.visibleCount))

        HStack(spacing: StripLayout.spacing) {
            ForEach(sampleItems) { item in
                SampleButton(item: item, taskbar: taskbar)
            }

            ForEach(Array(itemGroups.enumerated()), id: \.offset) { index, group in
                let shown = group.filter { item in visible.contains(where: { $0.id == item.id }) }
                if !shown.isEmpty {
                    // Marks where one display's windows end and the next
                    // display's begin. Keyed on whether anything has been drawn
                    // yet rather than the group index, so an empty leading
                    // group does not produce a stray rule at the far left.
                    if index > firstShownGroupIndex(visible: visible) {
                        BarSeparator(height: taskbar.iconSize * 0.9)
                    }
                    ForEach(shown) { item in
                        TaskbarButtonView(
                            item: item,
                            taskbar: taskbar,
                            screenUUID: screenUUID,
                            width: layout.buttonWidth,
                            showsTitle: layout.showsTitles
                        )
                    }
                }
            }

            if !overflow.isEmpty {
                OverflowButton(items: overflow, height: taskbar.iconSize * 1.25)
            }
        }
    }
}

/// A visible rule between sections.
///
/// `Divider()` draws with the system separator colour, which over a
/// translucent bar is invisible — the group boundaries were being drawn all
/// along and simply could not be seen.
private struct BarSeparator: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color.primary.opacity(0.30))
            .frame(width: 2, height: height)
            .padding(.horizontal, 3)
    }
}

private struct StartButton: View {
    let iconSize: Double
    let screenUUID: String?
    @State private var isHovered = false

    var body: some View {
        Button {
            let screen = NSScreen.screens.first { ScreenIdentity(screen: $0)?.uuid == screenUUID }
            StartMenuPanelController.shared.toggle(anchorScreen: screen ?? NSScreen.main)
        } label: {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: iconSize * 0.62, weight: .medium))
                .frame(width: iconSize * 1.5, height: iconSize * 1.25)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(isHovered ? 0.22 : 0.12))
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Start")
    }
}

private struct SampleButton: View {
    let item: TaskbarChrome.SampleItem
    let taskbar: TaskbarSettings

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.symbol)
                .font(.system(size: taskbar.iconSize * 0.66))
            if taskbar.showsWindowTitles {
                Text(item.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: taskbar.iconSize * 1.25)
        .frame(maxWidth: taskbar.showsWindowTitles ? taskbar.maxButtonWidth : nil)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(item.isActive ? 0.16 : 0.07))
        }
        .overlay(alignment: .bottom) {
            // Windows marks the focused window with an underline; it reads at a
            // glance in a way a background tint alone does not.
            if item.isActive {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
        }
    }
}

