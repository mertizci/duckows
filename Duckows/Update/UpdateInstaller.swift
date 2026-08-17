import AppKit
import Foundation
import Security

enum UpdateInstallError: LocalizedError {
    case mountFailed
    case appNotFoundInDMG
    case signatureInvalid
    case stagingFailed
    case destinationNotWritable

    var errorDescription: String? {
        switch self {
        case .mountFailed:
            return "Could not open the downloaded installer."
        case .appNotFoundInDMG:
            return "The installer did not contain Duckows."
        case .signatureInvalid:
            return "The downloaded update failed signature verification and was rejected."
        case .stagingFailed:
            return "Could not prepare the update for installation."
        case .destinationNotWritable:
            return "Duckows can't update itself in its current location."
        }
    }
}

/// Mounts a downloaded DMG, verifies the contained app is signed by the
/// expected Developer ID team, stages a verified copy, then swaps it into place
/// and relaunches.
struct UpdateInstaller {
    /// Developer ID team that legitimately signs Duckows. This value, together
    /// with the bundle identifier, is the app's designated requirement — the
    /// same one macOS uses to keep TCC grants across updates. Changing either
    /// breaks every installed copy's update path.
    private static let expectedTeamID = "NZDMMFNMU4"
    private static let bundleIdentifier = "com.duckows.app"
    private static let appName = "Duckows.app"

    // MARK: - Stage

    /// Mounts `dmgURL`, verifies the signature, copies the app to a staging
    /// directory, then detaches the image. Returns the staged `.app` URL.
    func prepareStagedApp(fromDMG dmgURL: URL) throws -> URL {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("dw-mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        try attach(dmg: dmgURL, at: mountPoint)
        defer { detach(mountPoint) }

        let appInDMG = mountPoint.appendingPathComponent(Self.appName)
        guard FileManager.default.fileExists(atPath: appInDMG.path) else {
            throw UpdateInstallError.appNotFoundInDMG
        }

        try verifySignature(of: appInDMG)

        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dw-staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stagedApp = stagingDir.appendingPathComponent(Self.appName)

        guard runDitto(from: appInDMG, to: stagedApp) else {
            throw UpdateInstallError.stagingFailed
        }

        return stagedApp
    }

    // MARK: - Install

    /// Swaps the running app bundle with `stagedApp` and relaunches.
    ///
    /// `beforeTerminate` runs on the main actor immediately before the process
    /// exits — Duckows uses it to put the system Dock back, so the seconds
    /// between this process dying and the new one launching are not spent with
    /// neither a Dock nor a taskbar on screen.
    ///
    /// This never returns on success: it terminates the current process so the
    /// detached script can replace the bundle while nothing holds it open.
    func installAndRelaunch(stagedApp: URL,
                            into destination: URL,
                            beforeTerminate: @escaping @MainActor () -> Void) throws {
        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateInstallError.destinationNotWritable
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dw-swap-\(UUID().uuidString).sh")
        try Self.swapScript.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            stagedApp.path,
            destination.path
        ]
        try process.run()

        Task { @MainActor in
            beforeTerminate()
            NSApp.terminate(nil)
        }
    }

    /// Replaces the bundle without ever leaving the destination missing.
    ///
    /// The obvious `rm -rf DEST && ditto SRC DEST` has a window in which no app
    /// exists at all; for an app that owns the user's Dock, a failure in that
    /// window strands them. Staging beside the destination and renaming twice
    /// keeps the gap to a single rename and makes failure rollback-able.
    private static let swapScript = """
    #!/bin/sh
    PID="$1"
    SRC="$2"
    DEST="$3"
    EXE="$DEST/Contents/MacOS/Duckows"

    # 1. Wait for the outgoing instance to exit, bounded at 60s.
    i=0
    while kill -0 "$PID" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.2; i=$((i+1)); done

    # 2. A login-item relaunch can race us and hold the bundle open. Give it a
    #    moment to settle, then insist.
    i=0
    while pgrep -f "$EXE" >/dev/null 2>&1 && [ "$i" -lt 100 ]; do sleep 0.2; i=$((i+1)); done
    pkill -f "$EXE" 2>/dev/null
    sleep 0.5

    # 3. Stage beside the destination, then rename into place.
    NEW="$DEST.dw-new"
    OLD="$DEST.dw-old"
    rm -rf "$NEW" "$OLD"
    if ditto "$SRC" "$NEW"; then
      # An agent app has no window to show a Gatekeeper prompt in, so a stray
      # quarantine flag would look like a silent hang.
      xattr -dr com.apple.quarantine "$NEW" 2>/dev/null
      if mv "$DEST" "$OLD" 2>/dev/null && mv "$NEW" "$DEST" 2>/dev/null; then
        rm -rf "$OLD"
      else
        [ -d "$OLD" ] && [ ! -e "$DEST" ] && mv "$OLD" "$DEST"
        rm -rf "$NEW"
      fi
    fi

    # 4. Relaunch, and confirm it actually came up.
    open "$DEST"
    i=0
    while [ "$i" -lt 75 ]; do
      pgrep -f "$EXE" >/dev/null 2>&1 && break
      sleep 0.2
      i=$((i+1))
    done

    # 5. One retry if it never started. The Dock was already restored before the
    #    old process exited, so the user is not left without one either way.
    if ! pgrep -f "$EXE" >/dev/null 2>&1; then
      open "$DEST"
    fi

    rm -rf "$(dirname "$SRC")"
    rm -f "$0"
    """

    // MARK: - hdiutil helpers

    private func attach(dmg: URL, at mountPoint: URL) throws {
        let result = run("/usr/bin/hdiutil", [
            "attach", dmg.path,
            "-nobrowse", "-noautoopen",
            "-mountpoint", mountPoint.path
        ])
        guard result == 0 else { throw UpdateInstallError.mountFailed }
    }

    private func detach(_ mountPoint: URL) {
        _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
    }

    private func runDitto(from source: URL, to destination: URL) -> Bool {
        run("/usr/bin/ditto", [source.path, destination.path]) == 0
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    // MARK: - Signature verification

    /// Confirms the app is signed by Apple's anchor with the expected bundle id
    /// and Developer ID team.
    ///
    /// This is the only defence against a tampered or spoofed download, and the
    /// one place in the app where a bug is a remote code execution vector.
    private func verifySignature(of appURL: URL) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            throw UpdateInstallError.signatureInvalid
        }

        let requirementText =
            "identifier \"\(Self.bundleIdentifier)\" and anchor apple generic and "
            + "certificate leaf[subject.OU] = \"\(Self.expectedTeamID)\""

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else {
            throw UpdateInstallError.signatureInvalid
        }

        let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures))
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, req, nil)
        guard status == errSecSuccess else {
            throw UpdateInstallError.signatureInvalid
        }
    }
}
