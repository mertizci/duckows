import AppKit
import SwiftUI

/// The Start menu, in the shape the old Windows ones had: a tall two-column
/// panel with programs on the left, places and settings on the right, and
/// search and power along the bottom.
///
/// Everything is a compact vertical list rather than a grid of large tiles —
/// that layout is what makes a long list of programs scannable, and it is what
/// was asked for.
struct StartMenuView: View {
    @ObservedObject private var catalog = AppCatalog.shared
    @ObservedObject private var pinned = DockPinnedApps.shared

    @State private var query = ""
    @State private var showsAllPrograms = false
    @State private var selection = 0
    @State private var results: [InstalledApp] = []
    @FocusState private var isSearchFocused: Bool

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftColumn
                Divider()
                rightColumn
            }
            Divider()
            bottomBar
        }
        .frame(width: 460, height: 540)
        .background {
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            query = ""
            showsAllPrograms = false
            selection = 0
            isSearchFocused = true
        }
        // Scoring in `body` would re-rank on every unrelated redraw.
        .onChange(of: query) { _, new in
            results = Self.search(new, in: catalog.apps)
            selection = 0
        }
        .onChange(of: catalog.apps) { _, apps in
            if isSearching { results = Self.search(query, in: apps) }
        }
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if isSearching {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, app in
                            AppRow(app: app, isSelected: index == selection) { launch(app) }
                        }
                        if results.isEmpty {
                            Text("Nothing matches “\(query)”.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 20)
                                .frame(maxWidth: .infinity)
                        }
                    } else if showsAllPrograms {
                        ForEach(catalog.grouped, id: \.category) { group in
                            Text(group.category.displayName.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 10)
                                .padding(.bottom, 3)
                            ForEach(group.apps) { app in
                                AppRow(app: app, isSelected: false) { launch(app) }
                            }
                        }
                    } else {
                        ForEach(pinned.apps) { app in
                            AppRow(app: app, isSelected: false) { launch(app) }
                        }
                        if pinned.apps.isEmpty {
                            Text("Nothing is pinned to your Dock.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(12)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Divider()

            // The hinge of the old Start menu: the short list you use, with
            // everything else one click away.
            Button {
                showsAllPrograms.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showsAllPrograms ? "chevron.left" : "square.grid.2x2")
                        .font(.system(size: 11))
                        .frame(width: 18)
                    Text(showsAllPrograms ? "Back" : "All Programs")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if !showsAllPrograms {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(HighlightRowStyle())
            .disabled(isSearching)
        }
        .frame(width: 268)
    }

    // MARK: - Right column

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(NSFullUserName())
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(PlaceShortcut.allCases) { place in
                ShortcutRow(title: place.displayName, symbol: place.symbolName) {
                    place.open()
                    StartMenuPanelController.shared.close()
                }
            }

            Divider().padding(.vertical, 6)

            ForEach(SystemSettingsPane.startMenuItems) { pane in
                ShortcutRow(title: pane.displayName, symbol: pane.symbolName) {
                    pane.open()
                    StartMenuPanelController.shared.close()
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search programs", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)
                .onSubmit(launchSelection)

            Spacer(minLength: 8)

            Menu {
                ForEach(PowerAction.allCases) { action in
                    Button {
                        StartMenuPanelController.shared.close()
                        PowerActionService.perform(action)
                    } label: {
                        Label(action.displayName, systemImage: action.symbolName)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power").font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.up").font(.system(size: 7))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Actions

    private static func search(_ query: String, in apps: [InstalledApp]) -> [InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return apps
            .compactMap { app -> (InstalledApp, Int)? in
                let byName = FuzzyMatcher.score(app.name, query: trimmed)
                let byIdentifier = FuzzyMatcher.score(app.id, query: trimmed).map { $0 / 4 }
                guard let best = [byName, byIdentifier].compactMap({ $0 }).max() else { return nil }
                return (app, best)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(50)
            .map(\.0)
    }

    private func launchSelection() {
        guard results.indices.contains(selection) else { return }
        launch(results[selection])
    }

    private func launch(_ app: InstalledApp) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                NSLog("Duckows: could not open \(app.name) – \(error.localizedDescription)")
            }
        }
        StartMenuPanelController.shared.close()
    }
}

// MARK: - Rows

private struct AppRow: View {
    let app: InstalledApp
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                // Cached: resolving this through Launch Services on every
                // redraw is what made the first version crawl.
                Image(nsImage: AppIconProvider.icon(forFile: app.url, size: 18))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(app.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(HighlightRowStyle(isSelected: isSelected))
    }
}

private struct ShortcutRow: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title).font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(HighlightRowStyle())
    }
}

/// A full-width row that lights up on hover, the way a menu row does.
private struct HighlightRowStyle: ButtonStyle {
    var isSelected = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
                    .padding(.horizontal, 4)
            }
            .onHover { isHovered = $0 }
    }

    private func fill(pressed: Bool) -> Color {
        if pressed { return Color.accentColor.opacity(0.35) }
        if isSelected { return Color.accentColor.opacity(0.28) }
        return isHovered ? Color.primary.opacity(0.10) : .clear
    }
}
