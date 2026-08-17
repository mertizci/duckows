import AppKit
import ApplicationServices

/// Keeps *maximized* windows out of the taskbar's strip, the way a Windows
/// taskbar reserves its work area — while leaving every other window alone.
///
/// macOS has no work area to reserve: `NSScreen.visibleFrame` is computed
/// inside AppKit from the Dock's rect and the menu bar height, neither of which
/// a third party can write. So the behaviour is reproduced after the fact.
///
/// The hard part is not the resize, it is deciding *when*. An earlier version
/// keyed off "does this window cover most of the screen", which also matches a
/// large window the user merely dragged downwards, so it resized windows that
/// were meant to be left alone. The signal used here is that **dragging moves a
/// window without resizing it**: only a size change — a zoom, a double-clicked
/// title bar, a Magnet-style snap — is treated as an attempt to fill the
/// screen.
@MainActor
final class MaximizeGuard {
    static let shared = MaximizeGuard()

    /// Last frame seen for each window, used to tell a resize from a move.
    private var previousFrames: [CGWindowID: CGRect] = [:]

    /// Windows we are mid-write on. Our own `AXUIElementSetAttributeValue`
    /// comes straight back as a resize notification, and without this the
    /// correction would retrigger itself forever.
    private var writeGuard: Set<CGWindowID> = []

    /// A window we corrected that immediately reclaimed the space is left
    /// alone: some apps insist on their own geometry, and a window that
    /// jitters is worse than one that overlaps.
    private var corrections: [CGWindowID: (count: Int, since: Date)] = [:]
    private var surrendered: Set<CGWindowID> = []

    private static let surrenderThreshold = 4
    private static let surrenderWindow: TimeInterval = 2.0

    /// How close to screen-filling counts as "being maximized".
    private static let fillWidthRatio: CGFloat = 0.97
    private static let fillHeightRatio: CGFloat = 0.93

    /// Ignore sub-pixel and rounding wobble when comparing sizes.
    private static let sizeEpsilon: CGFloat = 2

    private init() {}

    func reset() {
        previousFrames.removeAll()
        corrections.removeAll()
        surrendered.removeAll()
    }

    func forget(_ id: CGWindowID) {
        previousFrames.removeValue(forKey: id)
        corrections.removeValue(forKey: id)
        surrendered.remove(id)
    }

    func apply(to records: [WindowRecord]) {
        guard SettingsStore.shared.settings.general.keepsMaximizedWindowsClear,
              PermissionMonitor.shared.isAccessibilityTrusted else {
            // Still track frames, so turning the setting back on does not treat
            // every existing window as freshly maximized.
            records.forEach { previousFrames[$0.id] = $0.frame }
            return
        }

        let live = Set(records.map(\.id))
        previousFrames.keys.filter { !live.contains($0) }.forEach(forget)

        for record in records where !record.isMinimized && !record.isFullscreen {
            defer { previousFrames[record.id] = record.frame }

            guard !writeGuard.contains(record.id), !surrendered.contains(record.id) else { continue }
            guard let uuid = record.screenUUID,
                  let geometry = TaskbarPresenter.shared.geometry(forScreen: uuid) else { continue }
            guard record.frame.intersects(geometry.bar) else { continue }

            let previous = previousFrames[record.id]
            let didResize = previous.map {
                abs($0.width - record.frame.width) > Self.sizeEpsilon
                    || abs($0.height - record.frame.height) > Self.sizeEpsilon
            } ?? true // first sight: an already-maximized window still counts

            guard didResize, isFillingScreen(record.frame, geometry: geometry) else { continue }

            let target = record.frame.intersection(geometry.usable)
            guard target.width > 200, target.height > 200, target != record.frame else { continue }

            resize(record, to: target)
            previousFrames[record.id] = target
        }
    }

    /// True when the window is trying to occupy the whole display, rather than
    /// merely being large.
    private func isFillingScreen(_ frame: CGRect, geometry: ScreenGeometry) -> Bool {
        let full = geometry.usable.union(geometry.bar)
        return frame.width >= full.width * Self.fillWidthRatio
            && frame.height >= full.height * Self.fillHeightRatio
    }

    private func resize(_ record: WindowRecord, to frame: CGRect) {
        guard noteCorrection(record.id) else { return }

        writeGuard.insert(record.id)

        // Back to AX's top-left origin.
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        var origin = CGPoint(x: frame.minX, y: primaryMaxY - frame.maxY)
        var size = CGSize(width: frame.width, height: frame.height)

        if let value = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(record.element, kAXPositionAttribute as CFString, value)
        }
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(record.element, kAXSizeAttribute as CFString, value)
        }

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            self?.writeGuard.remove(record.id)
        }
    }

    private func noteCorrection(_ id: CGWindowID) -> Bool {
        let now = Date()
        var entry = corrections[id] ?? (0, now)
        if now.timeIntervalSince(entry.since) > Self.surrenderWindow {
            entry = (0, now)
        }
        entry.count += 1
        corrections[id] = entry

        if entry.count > Self.surrenderThreshold {
            surrendered.insert(id)
            NSLog("Duckows: window \(id) keeps reclaiming the bar's space – leaving it alone")
            return false
        }
        return true
    }
}
