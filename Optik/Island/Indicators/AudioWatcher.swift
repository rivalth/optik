import CoreAudio
import Foundation
import OptikCore

/// Output volume, the microphone and headphones coming and going, from Core
/// Audio's change notices. Nothing runs between changes.
@MainActor
final class AudioWatcher {
    var onVolume: ((Double, Bool) -> Void)?
    var onMicrophone: ((Bool) -> Void)?
    /// A device name and whether it connected (true) or left.
    var onAccessory: ((String, Bool) -> Void)?

    private let queue = DispatchQueue(label: "io.github.rivalth.optik.audio-watcher")
    private var output: AudioObjectID = 0
    private var input: AudioObjectID = 0
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        output = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        input = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.outputChanged() }
        listen(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice) { [weak self] in self?.inputChanged() }
        watchOutput()
        watchInput()
    }

    func stop() {
        for (object, address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
        }
        listeners = []
        isRunning = false
    }

    // MARK: Devices

    private func outputChanged() {
        let old = output
        output = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        guard output != old else { return }
        removeListeners(of: old)
        watchOutput()
        if Self.isWireless(output), let name = Self.name(of: output) {
            onAccessory?(name, true)
        } else if Self.isWireless(old), let name = Self.name(of: old) {
            onAccessory?(name, false)
        }
    }

    private func inputChanged() {
        let old = input
        input = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        guard input != old else { return }
        removeListeners(of: old)
        watchInput()
    }

    private func watchOutput() {
        let device = output
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            listen(device, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element) { [weak self] in
                self?.volumeChanged()
            }
        }
        listen(device, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput) { [weak self] in self?.volumeChanged() }
    }

    private func watchInput() {
        let device = input
        listen(device, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput) { [weak self] in self?.microphoneChanged() }
        listen(device, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeInput) { [weak self] in
            self?.microphoneChanged()
        }
    }

    private func volumeChanged() {
        let muted = Self.bool(kAudioDevicePropertyMute, of: output, scope: kAudioDevicePropertyScopeOutput) ?? false
        guard let level = Self.volume(of: output, scope: kAudioDevicePropertyScopeOutput) else { return }
        onVolume?(Double(level), muted)
    }

    private func microphoneChanged() {
        let muted = Self.bool(kAudioDevicePropertyMute, of: input, scope: kAudioDevicePropertyScopeInput) ?? false
        let level = Self.volume(of: input, scope: kAudioDevicePropertyScopeInput) ?? 1
        onMicrophone?(!muted && level > 0.001)
    }

    // MARK: Core Audio

    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                        _ action: @escaping @MainActor () -> Void) {
        guard object != 0 else { return }
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { action() } }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    private func removeListeners(of object: AudioObjectID) {
        listeners.removeAll { entry in
            guard entry.0 == object else { return false }
            var address = entry.1
            AudioObjectRemovePropertyListenerBlock(entry.0, &address, queue, entry.2)
            return true
        }
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    /// The main volume, or the average of the left and right channels on devices
    /// that only have those.
    private static func volume(of device: AudioObjectID, scope: AudioObjectPropertyScope) -> Float32? {
        if let main = float(kAudioDevicePropertyVolumeScalar, of: device, scope: scope, element: kAudioObjectPropertyElementMain) {
            return main
        }
        let channels = [1, 2].compactMap { float(kAudioDevicePropertyVolumeScalar, of: device, scope: scope, element: $0) }
        return channels.isEmpty ? nil : channels.reduce(0, +) / Float32(channels.count)
    }

    private static func float(_ selector: AudioObjectPropertySelector, of device: AudioObjectID,
                              scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Float32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func bool(_ selector: AudioObjectPropertySelector, of device: AudioObjectID,
                             scope: AudioObjectPropertyScope) -> Bool? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func isWireless(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var type = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard device != 0, AudioObjectGetPropertyData(device, &address, 0, nil, &size, &type) == noErr else { return false }
        return type == kAudioDeviceTransportTypeBluetooth || type == kAudioDeviceTransportTypeBluetoothLE
            || type == kAudioDeviceTransportTypeAirPlay
    }
}
