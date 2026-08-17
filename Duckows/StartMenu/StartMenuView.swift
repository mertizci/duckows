import AppKit
import SwiftUI

struct StartMenuView: View {
    @ObservedObject private var catalog = AppCatalog.shared
    @ObservedObject private var pinned = DockPinnedApps.shared

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var isSearchFocused: Bool

    /// Search results, or nil when the field is empty.
    private var results: [InstalledApp]? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return catalog.apps
            .compactMap { app -> (InstalledApp, Int)? in
                let byName = FuzzyMatcher.score(app.name, query: trimmed)
                let byIdentifier = FuzzyMatcher.score(app.id, query: trimmed).map { $0 / 4 }
                guard let best = [byName, byIdentifier].compactMap({ $0 }).max() else { return nil }
                return (app, best)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(40)
            .map(\.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let results {
                        section(title: "Results", apps: results, highlightSelection: true)
                        if results.isEmpty {
                            Text("Nothing matches “\(query)”.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        }
                    } else {
                        if !pinned.apps.isEmpty {
                            section(title: "Pinned to your Dock", apps: pinned.apps)
                        }
                        ForEach(catalog.grouped, id: \.category) { group in
                            section(title: group.category.displayName, apps: group.apps)
                        }
                        if !catalog.isLoaded {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 620, height: 560)
        .background {
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            query = ""
            selection = 0
            isSearchFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search apps", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isSearchFocused)
                .onSubmit(launchSelection)
                .onChange(of: query) { _, _ in selection = 0 }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func section(title: String, apps: [InstalledApp], highlightSelection: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                spacing: 8
            ) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    AppTile(app: app, isSelected: highlightSelection && index == selection) {
                        launch(app)
                    }
                }
            }
        }
    }

    private func launchSelection() {
        guard let results, results.indices.contains(selection) else { return }
        launch(results[selection])
    }

    private func launch(_ app: InstalledApp) {
        NSWorkspace.shared.openApplication(
            at: app.url,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                NSLog("Duckows: could not open \(app.name) – \(error.localizedDescription)")
            }
        }
        StartMenuPanelController.shared.close()
    }
}

private struct AppTile: View {
    let app: InstalledApp
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 40, height: 40)
                Text(app.name)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(app.name)
    }

    private var fill: Color {
        if isSelected { return Color.accentColor.opacity(0.28) }
        return isHovered ? Color.primary.opacity(0.09) : .clear
    }
}
