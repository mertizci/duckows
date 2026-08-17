import AppKit
import AudioToolbox
import CoreAudio

/// System output volume and which device it goes to.
///
/// CoreAudio invokes property listeners on its own threads, so everything that
/// touches published state hops back to the main actor.
///
/// Nothing happens in `init`: enumerating the HAL's devices is slow the first
/// time, and this object is first touched from inside a SwiftUI `body` on the
/// main thread while the bar is being built.
@MainActor
final class AudioMonitor: ObservableObject {
    static let shared = AudioMonitor()

    struct Device: Identifiable, Equatable, Sendable {
        let id: AudioDeviceID
        let name: String
    }

    @Published private(set) var volume: Float = 0
    @Published private(set) var isMuted = false
    @Published private(set) var devices: [Device] = []
    @Published private(set) var currentDeviceName = ""

    private var hasStarted = false
    /// What has been registered, so device listeners can be torn down when the
    /// default output changes.
    private var installed: [(object: AudioObjectID, address: AudioObjectPropertyAddress,
                             block: AudioObjectPropertyListenerBlock)] = []

    private init() {}

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        listen(to: AudioObjectID(kAudioObjectSystemObject),
               selector: kAudioHardwarePropertyDefaultOutputDevice,
               scope: kAudioObjectPropertyScopeGlobal)
        Task { await refresh() }
    }

    // MARK: - Reading

    func refresh() async {
        let reading = await Task.detached(priority: .utility) { () -> Reading in
            let device = Self.defaultOutputDevice()
            return Reading(
                volume: device.flatMap(Self.volume(of:)) ?? 0,
                isMuted: device.flatMap(Self.isMuted(of:)) ?? false,
                currentDeviceName: device.flatMap(Self.name(of:)) ?? "",
                devices: Self.outputDevices()
            )
        }.value
        volume = reading.volume
        isMuted = reading.isMuted
        currentDeviceName = reading.currentDeviceName
        devices = reading.devices
        followCurrentDevice()
    }

    private struct Reading: Sendable {
        let volume: Float
        let isMuted: Bool
        let currentDeviceName: String
        let devices: [Device]
    }

    func setVolume(_ value: Float) {
        guard let device = Self.defaultOutputDevice() else { return }
        Self.setVolume(value, on: device)
        volume = value
        if value > 0, isMuted { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        guard let device = Self.defaultOutputDevice() else { return }
        Self.setMuted(muted, on: device)
        isMuted = muted
    }

    func selectDevice(_ device: Device) {
        var id = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id
        )
        Task { await refresh() }
    }

    // MARK: - Listener

    /// Watch the device that is actually playing, so the icon tracks the volume
    /// keys and the menu bar's own slider rather than only noticing when the
    /// output device is swapped.
    private var followedDevice: AudioDeviceID?

    private func followCurrentDevice() {
        let device = Self.defaultOutputDevice()
        guard device != followedDevice else { return }
        // Only the per-device registrations are torn down; the system-object
        // one is what tells us the device changed in the first place.
        for entry in installed where entry.object != AudioObjectID(kAudioObjectSystemObject) {
            var address = entry.address
            AudioObjectRemovePropertyListenerBlock(entry.object, &address, DispatchQueue.main, entry.block)
        }
        installed.removeAll { $0.object != AudioObjectID(kAudioObjectSystemObject) }
        followedDevice = device

        guard let device else { return }
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                         kAudioDevicePropertyVolumeScalar,
                         kAudioDevicePropertyMute] {
            listen(to: device, selector: selector, scope: kAudioDevicePropertyScopeOutput)
        }
    }

    private func listen(to object: AudioObjectID, selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in await AudioMonitor.shared.refresh() }
        }
        guard AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr else {
            return
        }
        installed.append((object, address, block))
    }

    // MARK: - CoreAudio plumbing

    private nonisolated static func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != 0 ? device : nil
    }

    /// The property the menu bar slider maps to. Some aggregate and USB devices
    /// do not publish it, hence the per-device fallback.
    private nonisolated static func volume(of device: AudioDeviceID) -> Float? {
        if let value = scalar(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume) {
            return value
        }
        return scalar(device, kAudioDevicePropertyVolumeScalar)
    }

    private nonisolated static func scalar(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Float? {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private nonisolated static func setVolume(_ value: Float, on device: AudioDeviceID) {
        var volume = Float32(max(0, min(1, value)))
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                         kAudioDevicePropertyVolumeScalar] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectHasProperty(device, &address) else { continue }
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            AudioObjectSetPropertyData(device, &address, 0, nil,
                                       UInt32(MemoryLayout<Float32>.size), &volume)
            return
        }
    }

    private nonisolated static func isMuted(of device: AudioDeviceID) -> Bool? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value != 0 : nil
    }

    private nonisolated static func setMuted(_ muted: Bool, on device: AudioDeviceID) {
        var value: UInt32 = muted ? 1 : 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return }
        AudioObjectSetPropertyData(device, &address, 0, nil,
                                   UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private nonisolated static func name(of device: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        return status == noErr ? name as String : nil
    }

    private nonisolated static func outputDevices() -> [Device] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutputStreams(id), let name = name(of: id) else { return nil }
            return Device(id: id, name: name)
        }
    }

    /// Every device shows up in the list, including microphones; only the ones
    /// with output streams can be played through.
    private nonisolated static func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else {
            return false
        }
        let list = buffer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).contains { $0.mNumberChannels > 0 }
    }
}
