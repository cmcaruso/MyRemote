import HostCore
import Testing

@Suite("Phone Mic stream and jitter buffer")
struct MicBufferTests {
    @Test(arguments: [
        ("rate=24000", 24000.0), ("x=1&rate=16000", 16000), ("rate=22050", 22050),
    ])
    func readsTheRateFromTheQuery(_ query: String, _ rate: Double) {
        #expect(MicStream.rate(query: query) == rate)
    }

    @Test(arguments: [nil, "", "rate=", "rate=abc", "rate=4000", "rate=96000"] as [String?])
    func refusesAMissingOrUnusableRate(_ query: String?) {
        #expect(MicStream.rate(query: query) == nil)
    }

    @Test func decodesSixteenBitLittleEndianSamples() {
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x40, 0x00, 0x80, 0xFF, 0x7F, 0x01]
        #expect(MicStream.samples(bytes) == [0, 0.5, -1, Float(32767) / 32768])
    }

    @Test func playsSilenceUntilItHoldsTheTarget() {
        var buffer = MicBuffer(rate: 1000, targetSeconds: 0.01, limitSeconds: 0.1) // target 10, limit 100
        buffer.write(Array(repeating: 1, count: 9))
        #expect(buffer.read(4) == [0, 0, 0, 0])
        #expect(buffer.count == 9)
        buffer.write([1])
        #expect(buffer.playing)
        #expect(buffer.read(4) == [1, 1, 1, 1])
    }

    @Test func waitsForTheTargetAgainAfterRunningDry() {
        var buffer = MicBuffer(rate: 1000, targetSeconds: 0.01, limitSeconds: 0.1)
        buffer.write(Array(repeating: 1, count: 10))
        #expect(buffer.read(12) == Array(repeating: 1, count: 10) + [0, 0])
        #expect(!buffer.playing)
        buffer.write(Array(repeating: 2, count: 5))
        #expect(buffer.read(2) == [0, 0])
    }

    @Test func dropsTheOldestSamplesBackToTheTargetPastTheLimit() {
        var buffer = MicBuffer(rate: 1000, targetSeconds: 0.01, limitSeconds: 0.1)
        buffer.write(Array(repeating: 1, count: 100))
        #expect(buffer.count == 100)
        buffer.write(Array(repeating: 2, count: 5))
        #expect(buffer.count == 10)
        #expect(buffer.read(10) == Array(repeating: 1, count: 5) + Array(repeating: 2, count: 5))
    }

    @Test func keepsOrderAcrossManyWritesAndReads() {
        var buffer = MicBuffer(rate: 1000, targetSeconds: 0.004, limitSeconds: 0.1)
        var next: Float = 0, expected: Float = 0
        for _ in 0..<50 {
            buffer.write((0..<6).map { _ in next += 1; return next })
            for sample in buffer.read(5) where sample != 0 {
                expected += 1
                #expect(sample == expected)
            }
        }
        #expect(expected > 200)
    }
}
