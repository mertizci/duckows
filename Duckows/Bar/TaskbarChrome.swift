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
    /// Real window buttons. The settings preview leaves this empty and passes
    /// `sampleItems` instead.
    var items: [TaskbarItem] = []
    var needsAccessibility = false
    /// Stand-ins used only by the settings preview.
    var sampleItems: [SampleItem] = []
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
                Divider().frame(height: taskbar.iconSize * 0.8).opacity(0.4)
            }

            if needsAccessibility {
                GrantAccessChip()
            }

            // The strip scrolls rather than squeezing: a button whose title has
            // been compressed to nothing is no more useful than no button.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sampleItems) { item in
                        SampleButton(item: item, taskbar: taskbar)
                    }
                    ForEach(items) { item in
                        TaskbarButtonView(item: item, taskbar: taskbar, screenUUID: screenUUID)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if showsClock {
                TrayClock()
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BarBackground(appearance: appearance))
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

private struct TrayClock: View {
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 12, weight: .medium))
            Text(now, format: .dateTime.day().month().year())
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .padding(.horizontal, 8)
        .onReceive(tick) { now = $0 }
    }
}
