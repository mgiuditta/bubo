import AVFoundation
import Testing
@testable import Bubo

struct SpeechListenerTests {
    func buffer(amplitude: Float) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0..<4_800 { samples[index] = amplitude * sin(Float(index) * 0.1) }
        return buffer
    }

    @Test func silenceHasNoLevel() throws {
        #expect(SpeechListener.level(of: try buffer(amplitude: 0)) == 0)
    }

    @Test func louderIsHigherAndCapsAtOne() throws {
        let quiet = SpeechListener.level(of: try buffer(amplitude: 0.02))
        let loud = SpeechListener.level(of: try buffer(amplitude: 0.1))
        #expect(quiet > 0 && quiet < loud)
        #expect(SpeechListener.level(of: try buffer(amplitude: 1)) == 1)
    }
}
