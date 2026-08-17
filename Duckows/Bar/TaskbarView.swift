import SwiftUI

/// The bar's contents. Phase 0 renders the chrome only — the Start button, the
/// (empty) window strip and the clock — so the panel, theming and multi-display
/// behaviour can be verified before any Accessibility code exists.
struct TaskbarView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    private var appearance: AppearanceSettings { settingsStore.settings.appearance }
    private var taskbar: TaskbarSettings { settingsStore.settings.taskbar }

    var body: some View {
        HStack(spacing: 8) {
            StartButton()

            Divider().frame(height: 20).opacity(appearance.showsSeparator ? 0.4 : 0)

            // Window buttons land here in phase 3.
            Spacer(minLength: 0)

            TrayClock()
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BarBackground(appearance: appearance))
        .frame(height: appearance.barThickness)
        .environment(\.controlSize, taskbar.iconSize > 26 ? .large : .regular)
    }
}

private struct StartButton: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            // The Start menu arrives in phase 7.
        } label: {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 30)
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
