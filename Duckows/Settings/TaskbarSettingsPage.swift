import AppKit
import SwiftUI

struct TaskbarSettingsPage: View {
    @EnvironmentObject private var store: SettingsStore
    @ObservedObject private var screens = ScreenRegistry.shared

    @State private var draft: TaskbarSettings = SettingsStore.shared.settings.taskbar

    var body: some View {
        SettingsDetailScaffold(section: .taskbar) {
            SettingsCard(title: "Position") {
                SettingsOptionRow(title: "Screen edge") {
                    Picker("", selection: edgeBinding) {
                        ForEach(BarEdge.allCases) { edge in
                            Text(edge.displayName).tag(edge)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                SettingsToggleRow(
                    title: "Hide automatically",
                    subtitle: "Slides the bar away until you move the pointer to the edge.",
                    isOn: boolBinding(\.autoHide)
                )
            }

            SettingsCard(title: "Buttons") {
                SettingsToggleRow(
                    title: "Show window titles",
                    subtitle: "Off shows icons only, like the Dock.",
                    isOn: boolBinding(\.showsWindowTitles)
                )

                SettingsOptionRow(title: "Grouping") {
                    Picker("", selection: groupingBinding) {
                        ForEach(GroupingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                SettingsSliderRow(
                    title: "Icon size",
                    range: 16...40,
                    unit: " pt",
                    value: $draft.iconSize
                ) { new in store.updateSettings { $0.taskbar.iconSize = new.clamped(to: 16...40) } }

                SettingsSliderRow(
                    title: "Maximum button width",
                    range: 100...320,
                    unit: " pt",
                    value: $draft.maxButtonWidth
                ) { new in store.updateSettings { $0.taskbar.maxButtonWidth = new.clamped(to: 100...320) } }
            }

            SettingsCard(
                title: "Displays",
                subtitle: "Duckows puts an independent bar on each display."
            ) {
                SettingsOptionRow(title: "Which windows each bar shows") {
                    Picker("", selection: distributionBinding) {
                        ForEach(WindowDistribution.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }

                Text(draft.windowDistribution.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                SettingsToggleRow(
                    title: "Show on all displays",
                    subtitle: "Off shows the bar only on your main display.",
                    isOn: boolBinding(\.showsOnAllDisplays)
                )

                if draft.showsOnAllDisplays {
                    Divider()
                    ForEach(Array(screens.screens.enumerated()), id: \.offset) { _, screen in
                        if let identity = ScreenIdentity(screen: screen) {
                            SettingsToggleRow(
                                title: screen.localizedName,
                                subtitle: "\(Int(screen.frame.width)) × \(Int(screen.frame.height))",
                                isOn: displayBinding(identity)
                            )
                        }
                    }
                }
            }
        }
        .onAppear { draft = store.settings.taskbar }
        .onChange(of: store.settings.taskbar) { _, new in draft = new }
    }

    private var edgeBinding: Binding<BarEdge> {
        Binding(get: { draft.edge }, set: { draft.edge = $0; store.setBarEdge($0) })
    }

    private var distributionBinding: Binding<WindowDistribution> {
        Binding(
            get: { draft.windowDistribution },
            set: { draft.windowDistribution = $0; store.setWindowDistribution($0) }
        )
    }

    private var groupingBinding: Binding<GroupingMode> {
        Binding(get: { draft.grouping }, set: { draft.grouping = $0; store.setGrouping($0) })
    }

    private func boolBinding(_ keyPath: WritableKeyPath<TaskbarSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { new in
                draft[keyPath: keyPath] = new
                store.updateSettings { $0.taskbar[keyPath: keyPath] = new }
            }
        )
    }

    /// Stored as a disabled-list, so the toggle is inverted: a display the user
    /// has never seen is enabled by default.
    private func displayBinding(_ identity: ScreenIdentity) -> Binding<Bool> {
        Binding(
            get: { !draft.disabledDisplayUUIDs.contains(identity.uuid) },
            set: { isEnabled in
                var list = draft.disabledDisplayUUIDs
                if isEnabled {
                    list.removeAll { $0 == identity.uuid }
                } else if !list.contains(identity.uuid) {
                    list.append(identity.uuid)
                }
                draft.disabledDisplayUUIDs = list
                store.updateSettings { $0.taskbar.disabledDisplayUUIDs = list }
            }
        )
    }
}
