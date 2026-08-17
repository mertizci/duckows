import SwiftUI

/// Appearance controls with a live preview.
///
/// Slider values bind to a local draft so the preview tracks the drag at full
/// frame rate, and only the release commits to the store.
struct AppearanceSettingsPage: View {
    @EnvironmentObject private var store: SettingsStore

    @State private var draft: AppearanceSettings = SettingsStore.shared.settings.appearance
    @State private var tint: Color = .accentColor

    private var isGlassAvailable: Bool { BarStyle.glass.isAvailable }

    var body: some View {
        SettingsDetailScaffold(section: .appearance) {
            BarPreviewView(appearance: draft, taskbar: store.settings.taskbar)

            SettingsCard(title: "Material") {
                SettingsOptionRow(title: "Style") {
                    Picker("", selection: styleBinding) {
                        ForEach(BarStyle.allCases) { style in
                            Text(style.displayName)
                                .tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }

                if !isGlassAvailable {
                    StatusBanner(
                        style: .info,
                        message: "Liquid Glass needs macOS 26. On this Mac it falls back to Translucent."
                    )
                }

                SettingsSliderRow(
                    title: "Background opacity",
                    range: 0.15...1,
                    step: 0.01,
                    value: $draft.backgroundOpacity
                ) { store.setBackgroundOpacity($0) }
            }

            SettingsCard(title: "Tint", subtitle: "Blends a color into the bar's material.") {
                SettingsOptionRow(title: "Color") {
                    HStack(spacing: 8) {
                        ColorPicker("", selection: $tint, supportsOpacity: false)
                            .labelsHidden()
                            .onChange(of: tint) { _, new in
                                draft.tintHex = new.hexString
                                store.setTintHex(new.hexString)
                            }
                        Button("None") {
                            draft.tintHex = nil
                            store.setTintHex(nil)
                        }
                        .controlSize(.small)
                        .disabled(draft.tintHex == nil)
                    }
                }

                SettingsSliderRow(
                    title: "Tint strength",
                    range: 0...1,
                    step: 0.01,
                    value: $draft.tintOpacity
                ) { store.setTintOpacity($0) }
            }

            SettingsCard(title: "Shape") {
                SettingsSliderRow(
                    title: "Height",
                    range: 32...80,
                    unit: " pt",
                    value: $draft.barThickness
                ) { store.setBarThickness($0) }

                SettingsSliderRow(
                    title: "Corner radius",
                    range: 0...24,
                    unit: " pt",
                    value: $draft.cornerRadius
                ) { store.setCornerRadius($0) }

                SettingsToggleRow(
                    title: "Show separator",
                    subtitle: "A divider between the Start button and your windows.",
                    isOn: separatorBinding
                )
            }

            HStack {
                Spacer()
                Button("Reset to defaults") {
                    store.updateSettings { $0.appearance = .default }
                    syncDraft()
                }
            }
        }
        .onAppear(perform: syncDraft)
        // Keeps the draft honest when something else changes the settings —
        // the Reset button, or a future import.
        .onChange(of: store.settings.appearance) { _, _ in syncDraft() }
    }

    private var styleBinding: Binding<BarStyle> {
        Binding(
            get: { draft.style },
            set: { draft.style = $0; store.setBarStyle($0) }
        )
    }

    private var separatorBinding: Binding<Bool> {
        Binding(
            get: { draft.showsSeparator },
            set: { new in
                draft.showsSeparator = new
                store.updateSettings { $0.appearance.showsSeparator = new }
            }
        )
    }

    private func syncDraft() {
        draft = store.settings.appearance
        tint = draft.tintHex.flatMap(Color.init(hex:)) ?? .accentColor
    }
}

/// Renders the real `TaskbarChrome` at the configured height so the preview
/// cannot drift from the shipping bar.
struct BarPreviewView: View {
    let appearance: AppearanceSettings
    let taskbar: TaskbarSettings

    private let sample: [TaskbarChrome.SampleItem] = [
        .init(symbol: "safari", title: "Duckows — GitHub", isActive: true),
        .init(symbol: "terminal", title: "zsh — 80×24"),
        .init(symbol: "folder", title: "Projects")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            ZStack {
                PreviewBackdrop()
                TaskbarChrome(appearance: appearance, taskbar: taskbar, sampleItems: sample)
                    .frame(height: appearance.barThickness)
                    .frame(maxHeight: .infinity, alignment: taskbar.edge == .bottom ? .bottom : .top)
            }
            .frame(height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }
}

/// A stand-in for the desktop. Translucent materials sample whatever is behind
/// the window, so previewing them over a flat color would misrepresent them —
/// this at least gives the blur some contrast to work with.
private struct PreviewBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color.orange.opacity(0.55), Color.purple.opacity(0.55), Color.blue.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            GeometryReader { geo in
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: geo.size.width * 0.22)
                        .offset(
                            x: geo.size.width * (0.08 + 0.17 * Double(index)),
                            y: geo.size.height * (index.isMultiple(of: 2) ? 0.12 : 0.42)
                        )
                }
            }
        }
    }
}

extension Color {
    /// `#RRGGBB` for persistence. Converted through sRGB because the picker can
    /// hand back a color in a different space, which `NSColor` refuses to read
    /// component-wise.
    var hexString: String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
