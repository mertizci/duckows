import SwiftUI

/// The sections of the settings window sidebar.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case taskbar
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .taskbar: return "Taskbar"
        case .about: return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Startup and updates"
        case .appearance: return "Color, material, and size"
        case .taskbar: return "Position, buttons, and displays"
        case .about: return "Version and support"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .taskbar: return "rectangle.bottomthird.inset.filled"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Scaffolding

/// Page title and blurb, sitting above the cards.
struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A scrolling page body with the house padding and a readable max width.
struct SettingsDetailScaffold<Content: View>: View {
    let section: SettingsSection
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsPageHeader(title: section.title, subtitle: section.subtitle)
                content
            }
            .frame(maxWidth: 660, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

/// A titled group of related controls.
struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

/// A labelled row with an arbitrary trailing control.
struct SettingsOptionRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        SettingsOptionRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!isEnabled)
        }
    }
}

/// A slider that updates its binding continuously but only commits on release.
///
/// Sliders fire at display rate while dragging; committing every frame would
/// mean a disk write and a full bar relayout per frame.
struct SettingsSliderRow: View {
    let title: String
    var subtitle: String?
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = ""
    @Binding var value: Double
    let onCommit: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(formatted)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step) { isEditing in
                if !isEditing { onCommit(value) }
            }
        }
    }

    private var formatted: String {
        let rounded = (value / step).rounded() * step
        let text = step < 1 ? String(format: "%.2f", rounded) : String(Int(rounded))
        return unit.isEmpty ? text : "\(text)\(unit)"
    }
}

/// An inline status message. `.info` exists for the cases where macOS simply
/// does not allow what the user is asking for, and saying so is better than a
/// control that silently does nothing.
struct StatusBanner: View {
    enum Style {
        case success
        case warning
        case info

        var symbol: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .info: return .accentColor
            }
        }
    }

    let style: Style
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.symbol)
                .foregroundStyle(style.tint)
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(style.tint.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style.tint.opacity(0.25), lineWidth: 1)
        }
    }
}
