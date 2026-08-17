import AppKit
import Foundation

/// The user-facing state of the update flow, consumed by `UpdaterView`.
enum UpdateState: Equatable {
    case idle
    case checking
    case available(GitHubRelease)
    case downloading(Double)
    case installing
    case upToDate
    case failed(String)
    case justUpdated(version: String, notes: String)

    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking), (.installing, .installing), (.upToDate, .upToDate):
            return true
        case let (.available(l), .available(r)):
            return l.tagName == r.tagName
        case let (.downloading(l), .downloading(r)):
            return l == r
        case let (.failed(l), .failed(r)):
            return l == r
        case let (.justUpdated(lv, ln), .justUpdated(rv, rn)):
            return lv == rv && ln == rn
        default:
            return false
        }
    }
}

/// Orchestrates the check → prompt → download → install → relaunch flow and the
/// post-update notice.
@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    @Published private(set) var state: UpdateState = .idle

    private let service: GitHubReleaseService
    private let installer = UpdateInstaller()
    private var isWorking = false

    private static let pendingUpdateKey = "Duckows.pendingUpdate"
    private static let forceCheckKey = "Duckows.forceUpdateCheck"

    private struct PendingUpdate: Codable {
        let version: String
        let notes: String
    }

    init(service: GitHubReleaseService = GitHubReleaseService()) {
        self.service = service
    }

    // MARK: - Current version

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// project.yml pins local builds to 0.0.0, so a dev build would see every
    /// published release as newer and nag on every launch.
    private var isDevBuild: Bool { currentVersion == "0.0.0" }

    // MARK: - Checking

    /// The automatic launch check. Skipped for dev builds unless forced with
    /// `defaults write com.duckows.app Duckows.forceUpdateCheck -bool YES`.
    func checkForUpdatesOnLaunch() {
        guard !isDevBuild || UserDefaults.standard.bool(forKey: Self.forceCheckKey) else { return }
        checkForUpdates(silent: true)
    }

    /// Checks GitHub for a newer release. When `silent`, nothing is shown unless
    /// an update is actually available.
    func checkForUpdates(silent: Bool) {
        guard !isWorking else { return }
        isWorking = true
        state = .checking

        Task {
            defer { isWorking = false }
            do {
                let release = try await service.latestRelease()
                guard let latest = SemanticVersion(release.tagName),
                      let current = SemanticVersion(currentVersion) else {
                    finishCheck(silent: silent, result: .upToDate)
                    return
                }

                // An update is only offered when BOTH a newer version exists AND
                // that release ships a downloadable .dmg asset.
                if latest > current, service.dmgAsset(in: release) != nil {
                    state = .available(release)
                    UpdaterWindowController.shared.show()
                } else {
                    finishCheck(silent: silent, result: .upToDate)
                }
            } catch {
                finishCheck(silent: silent, result: .failed(error.localizedDescription))
            }
        }
    }

    private func finishCheck(silent: Bool, result: UpdateState) {
        if silent {
            state = .idle
            // A silent check must never leave a window on screen. Something
            // else may already have opened it — the post-update notice does —
            // and an idle updater window has nothing to say.
            UpdaterWindowController.shared.close()
        } else {
            state = result
            UpdaterWindowController.shared.show()
        }
    }

    // MARK: - Download & install

    func startDownload(_ release: GitHubRelease) {
        guard !isWorking else { return }
        isWorking = true

        Task {
            defer { isWorking = false }
            do {
                guard let asset = service.dmgAsset(in: release) else {
                    throw GitHubReleaseError.noDMGAsset
                }

                // Persist now so the post-update popup works even offline later.
                persistPendingUpdate(version: release.displayVersion, notes: release.releaseNotes)

                state = .downloading(0)
                let downloader = UpdateDownloader()
                let dmgURL = try await downloader.download(asset.browserDownloadURL) { [weak self] fraction in
                    self?.state = .downloading(fraction)
                }

                state = .installing
                let staged = try await Task.detached(priority: .userInitiated) {
                    try UpdateInstaller().prepareStagedApp(fromDMG: dmgURL)
                }.value

                try? FileManager.default.removeItem(at: dmgURL)

                // Replaces the bundle and relaunches; terminates this process.
                try installer.installAndRelaunch(stagedApp: staged, into: Bundle.main.bundleURL) {
                    // Hand the Dock back before dying. The relaunched instance
                    // takes it over again, so the user sees a brief flash rather
                    // than a Mac with neither a Dock nor a taskbar.
                    DockRestoreHook.shared.restoreBeforeExit()
                }
            } catch let error as UpdateInstallError where error == .destinationNotWritable {
                clearPendingUpdate()
                state = .failed(error.localizedDescription)
                openReleasesPage()
            } catch {
                clearPendingUpdate()
                state = .failed(error.localizedDescription)
            }
        }
    }

    func dismiss() {
        state = .idle
        UpdaterWindowController.shared.close()
    }

    // MARK: - Post-update notice

    /// If the app was just relaunched into the version we updated to, surfaces
    /// the "Updated to vX.Y.Z" popup with release notes, then clears the flag.
    ///
    /// Returns whether a notice was shown, so the caller can skip the automatic
    /// launch check: it would overwrite the notice with a spinner, and there is
    /// self-evidently nothing newer to find right after updating.
    @discardableResult
    func consumePostUpdateNoticeIfNeeded() -> Bool {
        guard let pending = loadPendingUpdate() else { return false }
        clearPendingUpdate()

        guard let pendingVersion = SemanticVersion(pending.version),
              let current = SemanticVersion(currentVersion),
              current >= pendingVersion else {
            return false
        }

        state = .justUpdated(version: pending.version, notes: pending.notes)
        UpdaterWindowController.shared.show()
        return true
    }

    // MARK: - Persistence

    private func persistPendingUpdate(version: String, notes: String) {
        let pending = PendingUpdate(version: version, notes: notes)
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.pendingUpdateKey)
        }
    }

    private func loadPendingUpdate() -> PendingUpdate? {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingUpdateKey) else { return nil }
        return try? JSONDecoder().decode(PendingUpdate.self, from: data)
    }

    private func clearPendingUpdate() {
        UserDefaults.standard.removeObject(forKey: Self.pendingUpdateKey)
    }

    private func openReleasesPage() {
        let url = URL(string: "https://github.com/\(GitHubReleaseService.repository)/releases/latest")!
        NSWorkspace.shared.open(url)
    }
}

/// Indirection so the updater does not depend on the Dock module, which lands
/// in a later phase. `DockController` registers itself here once it exists.
@MainActor
final class DockRestoreHook {
    static let shared = DockRestoreHook()

    private var handler: (() -> Void)?

    private init() {}

    func register(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func restoreBeforeExit() {
        handler?()
    }
}
