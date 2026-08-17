import AppKit
import CoreWLAN

/// Wi-Fi power, signal, and — when macOS allows it — the network name.
///
/// The name is the awkward part. CoreWLAN's own header says SSID is withheld
/// unless Location Services is on and this app is authorised, and there are
/// enough reports of it returning nil even then that it is treated as a
/// garnish: the widget's real state is power and signal strength, both of
/// which need no permission at all.
///
/// Nothing happens in `init`. Every tray monitor is first touched from inside a
/// SwiftUI `body`, on the main thread, while the bar's content view is being
/// installed — work there blocks the bar from ever appearing.
@MainActor
final class WiFiMonitor: ObservableObject {
    static let shared = WiFiMonitor()

    @Published private(set) var isPoweredOn = false
    @Published private(set) var isPresent = false
    /// Nil when macOS will not tell us, which is not the same as disconnected.
    @Published private(set) var networkName: String?
    /// 0 to 3 bars, or nil when not associated.
    @Published private(set) var bars: Int?

    private var timer: Task<Void, Never>?

    private init() {}

    func start() {
        guard timer == nil else { return }
        // CoreWLAN's event API needs a delegate on a run loop and misses
        // roaming anyway; a slow poll is both simpler and honest about how
        // fresh the reading is.
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func refresh() async {
        let reading = await Task.detached(priority: .utility) { Self.read() }.value
        isPresent = reading != nil
        guard let reading else { return }
        isPoweredOn = reading.isPoweredOn
        networkName = reading.name
        bars = reading.bars
    }

    private nonisolated static func read() -> (isPoweredOn: Bool, name: String?, bars: Int?)? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        guard interface.powerOn() else { return (false, nil, nil) }
        let rssi = interface.rssiValue()
        // 0 means not associated; the usable range is roughly -30 to -90.
        let bars = rssi == 0 ? nil : max(0, min(3, (rssi + 90) / 15))
        return (true, interface.ssid(), bars)
    }

    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
    }
}

/// The two headerless IOBluetooth entry points, resolved at runtime.
///
/// Kept out of `BluetoothMonitor` so they can be called from a background
/// thread without touching main-actor state — see the comment on `refresh()`.
private enum IOBluetoothSymbols {
    typealias GetPowerFn = @convention(c) (UnsafeMutablePointer<Int32>) -> Int32
    typealias SetPowerFn = @convention(c) (Int32) -> Int32

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY
    )

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    /// `dlopen`/`dlsym` alone are inert — neither starts the CoreBluetooth
    /// machinery, so probing availability costs nothing and prompts nothing.
    static let isPresent: Bool = symbol("IOBluetoothPreferenceGetControllerPowerState", as: GetPowerFn.self) != nil

    static func getPower() -> Bool? {
        guard let fn = symbol("IOBluetoothPreferenceGetControllerPowerState", as: GetPowerFn.self) else { return nil }
        var state: Int32 = 0
        _ = fn(&state)
        return state != 0
    }

    static func setPower(_ on: Bool) -> Bool {
        guard let fn = symbol("IOBluetoothPreferenceSetControllerPowerState", as: SetPowerFn.self) else { return false }
        _ = fn(on ? 1 : 0)
        return true
    }
}

/// Bluetooth power state and toggle.
///
/// `IOBluetoothPreferenceGetControllerPowerState` is exported by
/// IOBluetooth.framework but declared in no public header, so it is resolved at
/// runtime — if it ever disappears the widget degrades to a link into Settings
/// rather than taking the app with it.
///
/// Two things about it are worth stating plainly, both learned the hard way on
/// macOS 26:
///
/// 1. It is **not** permission-free. IOBluetooth is now implemented on top of
///    CoreBluetooth, so the first call spins up `IOBluetoothCoreBluetoothCoordinator`
///    and hits the Bluetooth TCC gate. Without `NSBluetoothAlwaysUsageDescription`
///    the process is killed, not denied. Hence the key in Info.plist and the
///    widget being off by default.
/// 2. That first call blocks on a semaphore while the coordinator starts, so it
///    must never run on the main thread.
@MainActor
final class BluetoothMonitor: ObservableObject {
    static let shared = BluetoothMonitor()

    @Published private(set) var isPoweredOn = false
    @Published private(set) var isAvailable = false

    private var timer: Task<Void, Never>?

    private init() {}

    func start() {
        guard timer == nil else { return }
        isAvailable = IOBluetoothSymbols.isPresent
        guard isAvailable else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func refresh() async {
        guard let on = await Task.detached(priority: .utility, operation: {
            IOBluetoothSymbols.getPower()
        }).value else { return }
        isPoweredOn = on
    }

    func toggle() {
        let target = !isPoweredOn
        Task {
            let ok = await Task.detached(priority: .utility) {
                IOBluetoothSymbols.setPower(target)
            }.value
            guard ok else { return openSettings() }
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
        }
    }

    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }
}
