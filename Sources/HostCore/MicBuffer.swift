import Foundation

/// The Phone Mic's stream: the Remote opens `/mic?rate=24000` and sends binary WebSocket frames of
/// mono 16-bit little-endian PCM at that rate, about 20 ms each.
public enum MicStream {
    /// The sample rate a `/mic` request asks for, or nil if it's missing or outside 8–48 kHz.
    public static func rate(query: String?) -> Double? {
        guard let query else { return nil }
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0] == "rate", let rate = Int(parts[1]), (8000...48000).contains(rate)
            else { continue }
            return Double(rate)
        }
        return nil
    }

    /// One frame's samples, -1 to 1; a trailing odd byte is dropped.
    public static func samples(_ bytes: some Collection<UInt8>) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(bytes.count / 2)
        var low: UInt8?
        for byte in bytes {
            if let l = low {
                out.append(Float(Int16(bitPattern: UInt16(l) | UInt16(byte) << 8)) / 32768)
                low = nil
            } else {
                low = byte
            }
        }
        return out
    }
}

/// The jitter buffer between the network and the audio output.
///
/// Frames arrive in bursts over TCP; the output pulls at a steady rate. The buffer waits until it holds
/// `target` samples before it plays, plays silence and waits again when it runs dry, and drops the oldest
/// samples back to `target` when it holds more than `limit`, so a stall never turns into lasting delay.
public struct MicBuffer: Sendable {
    public let target: Int
    public let limit: Int
    private var samples: [Float] = []
    private var start = 0 // index of the oldest unread sample
    public private(set) var playing = false

    /// Defaults for a speaking voice: about 60 ms of slack, at most 200 ms of delay.
    public init(rate: Double, targetSeconds: Double = 0.06, limitSeconds: Double = 0.2) {
        target = Int(rate * targetSeconds)
        limit = max(Int(rate * limitSeconds), target + 1)
    }

    /// Samples waiting to play.
    public var count: Int { samples.count - start }

    public mutating func write(_ new: [Float]) {
        if start > 0, start >= samples.count / 2 {
            samples.removeFirst(start)
            start = 0
        }
        samples += new
        if count > limit { start += count - target }
        if !playing, count >= target { playing = true }
    }

    /// The next `n` samples, padded with silence when there aren't enough.
    public mutating func read(_ n: Int) -> [Float] {
        Array(unsafeUninitializedCapacity: n) { out, initialized in
            read(into: out)
            initialized = n
        }
    }

    /// Fills `out` with the next samples, padded with silence; doesn't allocate, for the audio thread.
    public mutating func read(into out: UnsafeMutableBufferPointer<Float>) {
        let n = out.count
        guard playing else {
            out.initialize(repeating: 0)
            return
        }
        let available = min(n, count)
        samples.withUnsafeBufferPointer { source in
            for i in 0..<available { out[i] = source[start + i] }
        }
        start += available
        if available < n {
            for i in available..<n { out[i] = 0 }
            playing = false // ran dry: wait for `target` again
        }
    }
}
