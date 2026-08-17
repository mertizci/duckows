import SwiftUI

/// Which page the settings window is showing. Held outside the view so the
/// window controller can deep-link to a section without rebuilding the view.
@MainActor
final class SettingsSelection: ObservableObject {
    static let shared = SettingsSelection()

    @Published var section: SettingsSection = .general

    private init() {}
}

struct SettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    @ObservedObject private var selection = SettingsSelection.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 860, minHeight: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsSection.allCases) { section in
                SidebarRow(section: section, isSelected: selection.section == section) {
                    selection.section = section
                }
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 232)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch selection.section {
            case .general: GeneralSettingsPage()
            case .appearance: AppearanceSettingsPage()
            case .taskbar: TaskbarSettingsPage()
            case .about: AboutSettingsPage()
            }
        }
        .environmentObject(store)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title).font(.system(size: 12, weight: .medium))
                    Text(section.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var fill: Color {
        if isSelected { return Color.accentColor.opacity(0.16) }
        return isHovered ? Color.primary.opacity(0.06) : .clear
    }
}
