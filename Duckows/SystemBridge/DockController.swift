import AppKit

/// Hides the macOS Dock while Duckows is running, and — the part that actually
/// matters — always gives it back.
///
/// Every exit path restores: a normal quit, a SIGTERM from `killall`, and the
/// next launch after a crash. The user's original setting is written to disk
/// *before* the first change, so a process that dies without restoring still
/// leaves enough behind for the next one to repair it.
@MainActor
final class DockController {
    static let shared = DockController()

    private var signalSources: [DispatchSourceSignal] = []

    private init() {}

    var isAvailable: Bool { CoreDockBridge.isAvailable }

    /// Called at launch, before anything is changed.
    ///
    /// A dirty flag left over from last time means the previous run died with
    /// the Dock hidden. The recorded value is still the user's real preference,
    /// so it is kept — reading the Dock now would only record Duckows' own
    /// leftovers as if the user had chosen them.
    func recoverFromCrashIfNeeded() {
        guard let snapshot = SettingsStore.shared.settings.dockRestore, snapshot.isDirty else { return }
        NSLog("Duckows: previous run left the Dock hidden – restoring it")
        CoreDockBridge.setAutoHideEnabled(snapshot.autoHide)
    }

    func apply() {
        if SettingsStore.shared.settings.general.hidesSystemDock {
            hide()
        } else {
            restore()
        }
    }

    func hide() {
        guard CoreDockBridge.isAvailable else { return }
        guard let current = CoreDockBridge.isAutoHideEnabled else { return }

        // Snapshot only on the way in. Doing it every time would overwrite the
        // user's real preference with our own once the Dock is already hidden.
        if SettingsStore.shared.settings.dockRestore?.isDirty != true {
            SettingsStore.shared.setDockRestoreState(
                DockRestoreState(autoHide: current, isDirty: true)
            )
        }

        CoreDockBridge.setAutoHideEnabled(true)
        installSignalHandlers()
    }

    func restore() {
        guard let snapshot = SettingsStore.shared.settings.dockRestore, snapshot.isDirty else { return }
        CoreDockBridge.setAutoHideEnabled(snapshot.autoHide)
        SettingsStore.shared.setDockRestoreState(
            DockRestoreState(autoHide: snapshot.autoHide, isDirty: false)
        )
    }

    /// `killall Duckows` never reaches `applicationWillTerminate`, which would
    /// leave the Dock hidden with no obvious way back.
    private func installSignalHandlers() {
        guard signalSources.isEmpty else { return }
        for code in [SIGTERM, SIGINT] {
            signal(code, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: code, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    DockController.shared.restore()
                    SettingsStore.shared.saveNow()
                }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
