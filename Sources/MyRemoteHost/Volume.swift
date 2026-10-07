import AudioToolbox
import CoreAudio
import Foundation
import HostCore

/// The default output device's volume through CoreAudio: read it, set it, and hear about changes,
/// including the default device switching (headphones, AirPlay, HDMI).
@MainActor
final class Volume {
    /// Called on the main actor whenever the level, mute or output device changes.
    var onChange: (() -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static var levelAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    init() {
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.followDefaultDevice() }
        }
        followDefaultDevice()
    }

    func current() -> VolumeState {
        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let hasLevel = AudioObjectGetPropertyData(device, &Self.levelAddress, 0, nil, &size, &level) == noErr

        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &muted) != noErr { muted = 0 }

        var settable: DarwinBoolean = false
        if hasLevel, AudioObjectIsPropertySettable(device, &Self.levelAddress, &settable) != noErr { settable = false }

        return VolumeState(level: hasLevel ? Double(level) : 1, muted: muted != 0, settable: hasLevel && settable.boolValue)
    }

    /// Sets the level, 0 to 1. Silently does nothing on outputs without software volume.
    func set(_ level: Double) {
        var value = Float32(level)
        AudioObjectSetPropertyData(device, &Self.levelAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    private func followDefaultDevice() {
        for (address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
        }
        deviceListeners = []

        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, 0, nil, &size, &id)
        device = id

        for address in [Self.levelAddress, Self.muteAddress] {
            var address = address
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.onChange?() }
            }
            if AudioObjectAddPropertyListenerBlock(device, &address, .main, block) == noErr {
                deviceListeners.append((address, block))
            }
        }
        onChange?()
    }
}
