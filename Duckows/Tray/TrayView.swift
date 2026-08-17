import AppKit
import SwiftUI

/// The right-hand end of the bar.
///
/// Anything whose data needs a permission that has not been granted, or
/// hardware this Mac does not have, hides itself rather than showing a blank —
/// an empty battery on a desktop is worse than no battery at all.
struct TrayView: View {
    let tray: TraySettings
    let iconSize: Double

    private var enabled: [TrayWidgetKind] { tray.widgets.filter(\.isEnabled).map(\.kind) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tray.widgets.filter(\.isEnabled)) { config in
                switch config.kind {
                case .systemLoad: SystemLoadWidget()
                case .wifi:       WiFiWidget()
                case .bluetooth:  BluetoothWidget()
                case .volume:     VolumeWidget()
                case .battery:    BatteryWidget()
                case .clock:      ClockWidget(tray: tray)
                }
            }
        }
        .font(.system(size: 11))
        // The tray starts the monitors, not the widgets. A widget with no data
        // yet draws nothing, and SwiftUI runs no lifecycle on a view that
        // produced no content — so a widget that waits for its monitor before
        // appearing would never start the monitor it is waiting for. Here there
        // is always a container, and enabling a widget in Settings starts its
        // monitor without a relaunch.
        .task(id: enabled) { syncMonitors() }
    }

    private func syncMonitors() {
        let on = Set(enabled)
        for kind in TrayWidgetKind.allCases {
            let wanted = on.contains(kind)
            switch kind {
            case .systemLoad: wanted ? SystemLoadMonitor.shared.start() : SystemLoadMonitor.shared.stop()
            case .wifi:       wanted ? WiFiMonitor.shared.start() : WiFiMonitor.shared.stop()
            case .bluetooth:  wanted ? BluetoothMonitor.shared.start() : BluetoothMonitor.shared.stop()
            case .volume:     if wanted { AudioMonitor.shared.start() }
            case .battery:    if wanted { BatteryMonitor.shared.start() }
            case .clock:      break
            }
        }
    }
}

/// Shared chrome: a hover highlight and a popover, so every widget behaves the
/// same way under the pointer.
struct TrayButton<Label: View, Content: View>: View {
    /// Identifies the widget to the shared popover, so clicking the same one
    /// twice closes it instead of reopening it.
    let widget: TrayWidgetKind
    @ViewBuilder var label: Label
    @ViewBuilder var content: Content

    @State private var isHovered = false
    @State private var anchor = TrayAnchorBox()

    var body: some View {
        Button {
            TrayPopoverController.shared.toggle(
                widget: widget.rawValue, anchor: anchor.view, content: AnyView(content)
            )
        } label: {
            label
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.12 : 0))
                }
        }
        .buttonStyle(.plain)
        // Behind the button, not over it: the anchor exists only to report
        // where the widget is on screen, and must never take the click.
        .background(TrayAnchor(box: anchor))
        .onHover { isHovered = $0 }
    }
}

// MARK: - Clock

struct ClockWidget: View {
    let tray: TraySettings

    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        TrayButton(widget: .clock) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(now, format: timeFormat)
                    .font(.system(size: 12, weight: .medium))
                if tray.showsDate {
                    Text(now, format: .dateTime.day().month().year())
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
        } content: {
            CalendarPopover(month: now)
        }
        .onReceive(tick) { now = $0 }
    }

    private var timeFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.hour().minute()
        if tray.showsSeconds { style = style.second() }
        switch tray.clockFormat {
        case .system:         return style
        case .twelveHour:     return style.hour(.defaultDigits(amPM: .abbreviated))
        case .twentyFourHour: return style.hour(.twoDigits(amPM: .omitted))
        }
    }
}

private struct CalendarPopover: View {
    let month: Date

    private var days: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        // Blank cells so the first of the month lands under the right weekday.
        let leading = (calendar.component(.weekday, from: interval.start)
                       - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: interval.start)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(month, format: .dateTime.month(.wide).year())
                .font(.system(size: 13, weight: .semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26)), count: 7), spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let isToday = Calendar.current.isDateInToday(day)
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(.system(size: 11, weight: isToday ? .bold : .regular))
                            .frame(width: 24, height: 20)
                            .background {
                                if isToday {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.35))
                                }
                            }
                    } else {
                        Color.clear.frame(width: 24, height: 20)
                    }
                }
            }
        }
        .frame(width: 226)
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
}

// MARK: - Battery

struct BatteryWidget: View {
    @ObservedObject private var monitor = BatteryMonitor.shared

    var body: some View {
        Group {
            if let state = monitor.state {
                TrayButton(widget: .battery) {
                    HStack(spacing: 4) {
                        Image(systemName: symbol(for: state))
                            .font(.system(size: 12))
                        Text("\(state.percentage)%").monospacedDigit()
                    }
                } content: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(state.percentage)%").font(.system(size: 15, weight: .semibold))
                        if state.isCharging {
                            Text("Charging").foregroundStyle(.secondary)
                        } else if state.isPluggedIn {
                            Text("Plugged in").foregroundStyle(.secondary)
                        }
                        if let minutes = state.minutesRemaining {
                            Text("\(minutes / 60)h \(minutes % 60)m \(state.isCharging ? "until full" : "remaining")")
                                .foregroundStyle(.secondary)
                        }
                        Button("Battery Settings…") {
                            TrayPopoverController.shared.close()
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!
                            )
                        }
                        .controlSize(.small)
                    }
                    .font(.system(size: 11))
                    .frame(width: 170, alignment: .leading)
                }
            }
        }
    }

    private func symbol(for state: BatteryMonitor.State) -> String {
        if state.isCharging { return "battery.100.bolt" }
        switch state.percentage {
        case ..<15:  return "battery.0"
        case ..<40:  return "battery.25"
        case ..<70:  return "battery.50"
        case ..<90:  return "battery.75"
        default:     return "battery.100"
        }
    }
}

// MARK: - Volume

struct VolumeWidget: View {
    @ObservedObject private var monitor = AudioMonitor.shared

    var body: some View {
        TrayButton(widget: .volume) {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 15)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button {
                        monitor.setMuted(!monitor.isMuted)
                    } label: {
                        Image(systemName: symbol)
                    }
                    .buttonStyle(.plain)

                    Slider(
                        value: Binding(get: { Double(monitor.volume) },
                                       set: { monitor.setVolume(Float($0)) }),
                        in: 0...1
                    )
                }

                if !monitor.devices.isEmpty {
                    Divider()
                    Text("OUTPUT").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(monitor.devices) { device in
                        Button {
                            monitor.selectDevice(device)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: device.name == monitor.currentDeviceName
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(device.name == monitor.currentDeviceName
                                                     ? Color.accentColor : .secondary)
                                Text(device.name).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .font(.system(size: 11))
            .frame(width: 220, alignment: .leading)
        }
    }

    private var symbol: String {
        if monitor.isMuted || monitor.volume == 0 { return "speaker.slash" }
        switch monitor.volume {
        case ..<0.34: return "speaker.wave.1"
        case ..<0.67: return "speaker.wave.2"
        default:      return "speaker.wave.3"
        }
    }
}

// MARK: - Wi-Fi

struct WiFiWidget: View {
    @ObservedObject private var monitor = WiFiMonitor.shared

    var body: some View {
        Group {
            if monitor.isPresent {
                TrayButton(widget: .wifi) {
                    Image(systemName: monitor.isPoweredOn ? "wifi" : "wifi.slash")
                        .font(.system(size: 12))
                        .opacity(monitor.bars == nil && monitor.isPoweredOn ? 0.55 : 1)
                } content: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(status).font(.system(size: 12, weight: .medium))
                        // Only the name needs Location; the connection itself is
                        // always known, so the widget never claims to be off just
                        // because macOS is withholding the name.
                        if monitor.isPoweredOn, monitor.bars != nil, monitor.networkName == nil {
                            Text("macOS only reveals the network name to apps with Location access.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Wi-Fi Settings…") {
                            TrayPopoverController.shared.close()
                            monitor.openSettings()
                        }
                            .controlSize(.small)
                    }
                    .font(.system(size: 11))
                    .frame(width: 200, alignment: .leading)
                }
            }
        }
    }

    private var status: String {
        guard monitor.isPoweredOn else { return "Wi-Fi is off" }
        guard monitor.bars != nil else { return "Not connected" }
        return monitor.networkName ?? "Connected"
    }
}

// MARK: - Bluetooth

struct BluetoothWidget: View {
    @ObservedObject private var monitor = BluetoothMonitor.shared

    var body: some View {
        Group {
            if monitor.isAvailable {
                TrayButton(widget: .bluetooth) {
                    Image(systemName: monitor.isPoweredOn ? "wave.3.right" : "wave.3.right.circle")
                        .font(.system(size: 12))
                        .opacity(monitor.isPoweredOn ? 1 : 0.5)
                } content: {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Bluetooth", isOn: Binding(
                            get: { monitor.isPoweredOn },
                            set: { _ in monitor.toggle() }
                        ))
                        .toggleStyle(.switch)
                        Button("Bluetooth Settings…") {
                            TrayPopoverController.shared.close()
                            monitor.openSettings()
                        }
                            .controlSize(.small)
                    }
                    .font(.system(size: 11))
                    .frame(width: 180, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - CPU & memory

struct SystemLoadWidget: View {
    @ObservedObject private var monitor = SystemLoadMonitor.shared

    var body: some View {
        TrayButton(widget: .systemLoad) {
            HStack(spacing: 5) {
                Gauge(label: "C", value: monitor.cpuPercentage)
                Gauge(label: "M", value: monitor.memoryPercentage)
            }
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: "CPU %.0f%%", monitor.cpuPercentage))
                Text(String(format: "Memory %.0f%%", monitor.memoryPercentage))
                Button("Activity Monitor") {
                    TrayPopoverController.shared.close()
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                    )
                }
                .controlSize(.small)
            }
            .font(.system(size: 11))
            .frame(width: 150, alignment: .leading)
        }
    }

    private struct Gauge: View {
        let label: String
        let value: Double

        var body: some View {
            VStack(spacing: 1) {
                Text(label).font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 4, height: 16)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(value > 80 ? Color.orange : Color.accentColor)
                            .frame(height: max(2, 16 * value / 100))
                    }
            }
        }
    }
}
