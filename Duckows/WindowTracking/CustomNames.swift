import AppKit

/// User-chosen labels for taskbar buttons.
///
/// Held in memory on purpose. Window ids are handed out fresh each time an app
/// launches, so a name persisted to disk would sooner or later land on an
/// unrelated window — and a taskbar button quietly wearing the wrong name is
/// worse than one that forgot. Names last as long as the window does, and
/// there is a Reset Name item for changing your mind sooner.
@MainActor
final class CustomNames: ObservableObject {
    static let shared = CustomNames()

    @Published private(set) var names: [String: String] = [:]

    private init() {}

    func name(for itemID: String) -> String? {
        names[itemID]
    }

    func set(_ name: String, for itemID: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            names.removeValue(forKey: itemID)
        } else {
            names[itemID] = trimmed
        }
        WindowRegistry.shared.setNeedsRescan(.title)
    }

    func reset(_ itemID: String) {
        guard names.removeValue(forKey: itemID) != nil else { return }
        WindowRegistry.shared.setNeedsRescan(.title)
    }

    /// Drops names whose button no longer exists, so a closed window does not
    /// leave its label waiting for a reused id.
    func prune(keeping liveIDs: Set<String>) {
        let stale = names.keys.filter { !liveIDs.contains($0) }
        guard !stale.isEmpty else { return }
        stale.forEach { names.removeValue(forKey: $0) }
    }

    /// Asks for a new label.
    ///
    /// An agent app cannot put a modal in front of anything without being
    /// promoted first, so the policy is raised for the length of the sheet and
    /// dropped again afterwards.
    func promptToRename(itemID: String, currentTitle: String) {
        let alert = NSAlert()
        alert.messageText = "Rename this button"
        alert.informativeText = "Shown on the taskbar instead of the window's own title. "
            + "It lasts until the window closes."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = names[itemID] ?? currentTitle
        field.placeholderString = currentTitle
        alert.accessoryView = field

        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeFirstResponder(field)

        let response = alert.runModal()
        NSApp.setActivationPolicy(previousPolicy)

        guard response == .alertFirstButtonReturn else { return }
        set(field.stringValue, for: itemID)
    }
}
