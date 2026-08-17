import AppKit
import SwiftUI

/// `NSVisualEffectView` has no SwiftUI equivalent that exposes both `material`
/// and `blendingMode`; `.background(.ultraThinMaterial)` always blends within
/// the window, which is wrong for a bar that must sample the desktop behind it.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // The default, .followsWindowActiveState, would dim the bar whenever
        // another app is frontmost — which for an agent app is always.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// The taskbar's background: Liquid Glass on macOS 26, a vibrancy material on
/// 14–15, or a flat fill.
struct BarBackground: View {
    let appearance: AppearanceSettings

    private var tint: Color? {
        guard let hex = appearance.tintHex, appearance.tintOpacity > 0 else { return nil }
        return Color(hex: hex)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous)

        Group {
            switch appearance.style {
            case .glass:
                if #available(macOS 26, *) {
                    glassBackground(shape)
                } else {
                    materialBackground(shape)
                }
            case .translucent:
                materialBackground(shape)
            case .solid:
                shape.fill(Color(nsColor: .windowBackgroundColor))
            }
        }
        .overlay {
            // One tint mechanism for every style. `Glass.tint(_:)` was the
            // obvious choice for the macOS 26 path, but measuring the rendered
            // pixels showed it has no effect on a `Color.clear` host — a red
            // tint and a blue tint produced byte-identical output — so the
            // overlay does the work everywhere.
            //
            // .plusLighter rather than .normal: a normal overlay over a
            // vibrancy material flattens it into a dull wash.
            if let tint {
                shape.fill(tint.opacity(appearance.tintOpacity)).blendMode(.plusLighter)
            }
        }
        .compositingGroup()
        .opacity(appearance.backgroundOpacity)
    }

    @available(macOS 26, *)
    private func glassBackground(_ shape: some Shape) -> some View {
        Color.clear.glassEffect(.regular, in: shape)
    }

    private func materialBackground(_ shape: some Shape) -> some View {
        VisualEffectView(material: .headerView, blendingMode: .behindWindow)
            .clipShape(shape)
    }
}

extension Color {
    /// Parses `#RRGGBB` / `#RRGGBBAA`. Colors are stored as hex so config.json
    /// stays readable and diffable rather than holding an archived NSColor.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8,
              let raw = UInt64(value, radix: 16) else { return nil }

        let r, g, b, a: Double
        if value.count == 6 {
            r = Double((raw >> 16) & 0xFF) / 255
            g = Double((raw >> 8) & 0xFF) / 255
            b = Double(raw & 0xFF) / 255
            a = 1
        } else {
            r = Double((raw >> 24) & 0xFF) / 255
            g = Double((raw >> 16) & 0xFF) / 255
            b = Double((raw >> 8) & 0xFF) / 255
            a = Double(raw & 0xFF) / 255
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
