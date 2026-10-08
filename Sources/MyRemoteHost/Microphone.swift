import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import HostCore
import Synchronization

/// An audio output the Phone Mic can play into, by CoreAudio's stable UID.
struct OutputDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let object: AudioObjectID

    /// BlackHole 2ch is a virtual device: what plays into it, a call can pick as its microphone.
    var isBlackHole: Bool { name.hasPrefix("BlackHole") }
}

/// Hands the Phone Mic's samples from the network to the audio thread. Only the newest stream plays.
final class MicFeed: Sendable {
    private let state = Mutex<(stream: UUID, buffer: MicBuffer)?>(nil)

    func begin(_ stream: UUID, rate: Double) {
        state.withLock { $0 = (stream, MicBuffer(rate: rate)) }
    }

    func write(_ stream: UUID, _ samples: [Float]) {
        state.withLock { if $0?.stream == stream { $0?.buffer.write(samples) } }
    }

    /// Ends `stream`; false if a newer stream had already taken over.
    func end(_ stream: UUID) -> Bool {
        state.withLock {
            guard $0?.stream == stream else { return false }
            $0 = nil
            return true
        }
    }

    func read(into out: UnsafeMutableBufferPointer<Float>) {
        state.withLock {
            if $0 != nil { $0?.buffer.read(into: out) } else { out.initialize(repeating: 0) }
        }
    }
}

/// Plays the Phone Mic into the chosen output, BlackHole 2ch by default, without touching the Mac's
/// default output. Never the speakers unless picked: the user would hear themselves, and the phone would
/// pick that up again. The engine runs only while a Remote streams, so the device isn't held open otherwise.
@MainActor @Observable
final class Microphone {
    nonisolated let feed = MicFeed()
    private(set) var outputs: [OutputDevice] = []
    /// The live stream's sample rate; nil when no Remote is streaming.
    private(set) var rate: Double?
    private var current: UUID?
    private(set) var error: String?
    /// The output picked in the menu, by UID; nil until the user picks one.
    private(set) var chosen = UserDefaults.standard.string(forKey: "micOutput")

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var engineObserver: NSObjectProtocol?

    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    init() {
        AudioObjectAddPropertyListenerBlock(Self.system, &Self.devicesAddress, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.devicesChanged() }
        }
        outputs = Self.outputDevices()
    }

    var live: Bool { rate != nil }

    var blackHoleInstalled: Bool { outputs.contains(where: \.isBlackHole) }

    /// Where the Phone Mic plays: the chosen output, else BlackHole, else nowhere.
    var output: OutputDevice? {
        outputs.first { $0.id == chosen } ?? outputs.first(where: \.isBlackHole)
    }

    func choose(_ id: String) {
        chosen = id
        UserDefaults.standard.set(id, forKey: "micOutput")
        restart()
    }

    /// A Remote started `stream` at `rate`, or it ended (nil). An older stream ending changes nothing.
    func stream(_ stream: UUID, rate: Double?) {
        guard rate != nil || stream == current else { return }
        current = rate == nil ? nil : stream
        self.rate = rate
        restart()
    }

    private func devicesChanged() {
        let before = output
        outputs = Self.outputDevices()
        if output != before { restart() }
    }

    private func restart() {
        engine?.stop()
        engine = nil
        if let engineObserver { NotificationCenter.default.removeObserver(engineObserver) }
        engineObserver = nil
        guard let rate, let output else { return }

        let engine = AVAudioEngine()
        // Play into the chosen device, not the default output the engine would otherwise use.
        var device = output.object
        let status = engine.outputNode.audioUnit.map {
            AudioUnitSetProperty($0, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &device, UInt32(MemoryLayout<AudioObjectID>.size))
        } ?? kAudioUnitErr_Uninitialized
        guard status == noErr else {
            error = "can't play into \(output.name) (\(status))"
            return
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let source = Self.source(format: format, feed: feed)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            self.error = error.localizedDescription
            return
        }
        error = nil
        self.engine = engine
        // The engine stops when its device changes or goes away; start again, maybe on the fallback.
        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.outputs = Self.outputDevices()
                self?.restart()
            }
        }
    }

    /// Nonisolated, so the render block isn't tied to the main actor: it runs on the audio thread.
    private nonisolated static func source(format: AVAudioFormat, feed: MicFeed) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frames, list in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let out = UnsafeMutableBufferPointer(start: first, count: Int(frames))
            feed.read(into: out)
            for buffer in buffers.dropFirst() {
                buffer.mData?.copyMemory(from: first, byteCount: Int(frames) * MemoryLayout<Float>.size)
            }
            return noErr
        }
    }

    private static func outputDevices() -> [OutputDevice] {
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &devicesAddress, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamsSize) == noErr, streamsSize > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName)
            else { return nil }
            return OutputDevice(id: uid, name: name, object: id)
        }
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
