import AppKit
import IOKit.ps

/// Battery state, straight from IOKit.
///
/// Event-driven rather than polled: `IOPSNotificationCreateRunLoopSource` fires
/// when the power source actually changes, which for something that moves a
/// percent every few minutes is the difference between free and wasteful.
@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    struct State: Equatable {
        let percentage: Int
        let isCharging: Bool
        let isPluggedIn: Bool
        let minutesRemaining: Int?
    }

    /// Nil on a desktop Mac, where the widget hides itself rather than
    /// showing an empty battery.
    @Published private(set) var state: State?

    private var source: CFRunLoopSource?

    private init() {}

    /// Called from the widget's `.task`, never from `init`: every tray monitor
    /// is first touched from inside a SwiftUI `body` on the main thread while
    /// the bar's content view is being installed, and work there blocks the bar
    /// from ever appearing.
    func start() {
        guard source == nil else { return }
        refresh()

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.refresh() }
        }, context)?.takeRetainedValue() {
            self.source = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func refresh() {
        state = Self.read()
    }

    private static func read() -> State? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
                  maximum > 0 else { continue }

            let isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
            let powerState = description[kIOPSPowerSourceStateKey as String] as? String
            let isPluggedIn = powerState == (kIOPSACPowerValue as String)

            let remainingKey = isCharging
                ? kIOPSTimeToFullChargeKey as String
                : kIOPSTimeToEmptyKey as String
            let raw = description[remainingKey] as? Int
            // -1 means "still calculating", which is not a number to show.
            let minutes = (raw ?? -1) > 0 ? raw : nil

            return State(
                percentage: Int((Double(current) / Double(maximum) * 100).rounded()),
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                minutesRemaining: minutes
            )
        }
        return nil
    }
}

/// CPU and memory pressure.
///
/// Sampling is the only widget here that costs anything continuously, so it
/// only runs while it is switched on, and the arithmetic happens off the main
/// thread.
@MainActor
final class SystemLoadMonitor: ObservableObject {
    static let shared = SystemLoadMonitor()

    @Published private(set) var cpuPercentage: Double = 0
    @Published private(set) var memoryPercentage: Double = 0

    private var timer: Task<Void, Never>?
    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    private init() {}

    func start() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        previousTicks = nil
    }

    private func sample() async {
        let ticks = await Task.detached(priority: .utility) { Self.cpuTicks() }.value
        if let ticks {
            if let previous = previousTicks {
                let user = ticks.user &- previous.user
                let system = ticks.system &- previous.system
                let idle = ticks.idle &- previous.idle
                let nice = ticks.nice &- previous.nice
                let total = user + system + idle + nice
                if total > 0 {
                    cpuPercentage = Double(user + system + nice) / Double(total) * 100
                }
            }
            previousTicks = ticks
        }
        memoryPercentage = await Task.detached(priority: .utility) { Self.memoryUsage() }.value
    }

    private nonisolated static func cpuTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
        // HOST_CPU_LOAD_INFO_COUNT is a C macro, so it does not survive into
        // Swift; the size is the struct measured in integer_t words.
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (
            UInt64(info.cpu_ticks.0),
            UInt64(info.cpu_ticks.1),
            UInt64(info.cpu_ticks.2),
            UInt64(info.cpu_ticks.3)
        )
    }

    /// Apple's own "memory used" is not free + wired; the honest measure of
    /// pressure is what cannot be reclaimed — wired, compressed, and the pages
    /// still in active use.
    private nonisolated static func memoryUsage() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        return min(100, used / total * 100)
    }
}
