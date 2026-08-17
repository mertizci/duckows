import AppKit
import SwiftUI

struct TraySettingsPage: View {
    @EnvironmentObject private var store: SettingsStore

    @State private var draft: TraySettings = SettingsStore.shared.settings.tray

    var body: some View {
        SettingsDetailScaffold(section: .tray) {
            SettingsCard(title: "Widgets") {
                Text("Left to right, in the order they appear on the bar.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ForEach(Array(draft.widgets.enumerated()), id: \.element.id) { index, config in
                    SettingsOptionRow(title: config.kind.displayName) {
                        HStack(spacing: 6) {
                            Button {
                                move(from: index, to: index - 1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(index == 0)

                            Button {
                                move(from: index, to: index + 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(index == draft.widgets.count - 1)

                            Toggle("", isOn: enabledBinding(config.kind))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    if let note = note(for: config.kind) {
                        Text(note)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            SettingsCard(title: "Clock") {
                SettingsOptionRow(title: "Format") {
                    Picker("", selection: clockFormatBinding) {
                        ForEach(ClockFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                SettingsToggleRow(
                    title: "Show the date",
                    subtitle: "A second line under the time.",
                    isOn: boolBinding(\.showsDate)
                )

                SettingsToggleRow(
                    title: "Show seconds",
                    isOn: boolBinding(\.showsSeconds)
                )
            }

            SettingsCard(title: "Menu Bar Items") {
                SettingsToggleRow(
                    title: "Show other apps' menu bar icons here",
                    subtitle: "Third-party status icons appear in the bar, left of the widgets above. Apple's own — Wi-Fi, Bluetooth, Sound, Battery, the clock — are the native widgets above instead.",
                    isOn: boolBinding(\.mirrorsMenuBarItems)
                )

                if draft.mirrorsMenuBarItems {
                    SettingsToggleRow(
                        title: "Hide them from the menu bar",
                        subtitle: "Pushes the real icons off the right-hand end while Duckows runs. Two things to know: their menus still open at the top of the screen, because the owning app draws them there and no API can move them; and this relies on undocumented layout behaviour, so a macOS update could stop it working. Nothing is written on another app's behalf — quitting Duckows restores the menu bar.",
                        isOn: boolBinding(\.hidesMirroredItems)
                    )

                    StatusBanner(
                        style: .info,
                        message: "Duckows' own menu bar icon is hidden too. Settings and Quit move to the gear button in the Start menu."
                    )
                }
            }

            SettingsCard(title: "Battery") {
                SettingsToggleRow(
                    title: "Show the percentage",
                    subtitle: "Off shows the icon alone, the way Windows does.",
                    isOn: boolBinding(\.showsBatteryPercentage)
                )
            }
        }
        .onAppear { draft = store.settings.tray }
        .onChange(of: store.settings.tray) { _, new in draft = new }
    }

    /// Said plainly rather than discovered by surprise: these two are the only
    /// widgets that cost something to switch on.
    private func note(for kind: TrayWidgetKind) -> String? {
        switch kind {
        case .bluetooth:
            return "macOS asks for Bluetooth access the first time this is shown."
        case .systemLoad:
            return "Samples the CPU every two seconds while it is on."
        default:
            return nil
        }
    }

    private func move(from index: Int, to destination: Int) {
        guard draft.widgets.indices.contains(index),
              draft.widgets.indices.contains(destination) else { return }
        var widgets = draft.widgets
        widgets.swapAt(index, destination)
        draft.widgets = widgets
        store.updateSettings { $0.tray.widgets = widgets }
    }

    private func enabledBinding(_ kind: TrayWidgetKind) -> Binding<Bool> {
        Binding(
            get: { draft.widgets.first { $0.kind == kind }?.isEnabled ?? false },
            set: { isOn in
                guard let index = draft.widgets.firstIndex(where: { $0.kind == kind }) else { return }
                draft.widgets[index].isEnabled = isOn
                let widgets = draft.widgets
                store.updateSettings { $0.tray.widgets = widgets }
            }
        )
    }

    private var clockFormatBinding: Binding<ClockFormat> {
        Binding(
            get: { draft.clockFormat },
            set: { new in
                draft.clockFormat = new
                store.updateSettings { $0.tray.clockFormat = new }
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<TraySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { new in
                draft[keyPath: keyPath] = new
                store.updateSettings { $0.tray[keyPath: keyPath] = new }
            }
        )
    }
}
