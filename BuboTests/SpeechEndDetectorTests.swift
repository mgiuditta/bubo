import Foundation
import Testing
@testable import Bubo

/// When a sentence ends in a track: after 0.6 s of quiet that follows voice.
nonisolated struct SpeechEndDetectorTests {
    private static func quiet(_ seconds: Double) -> [Int16] { Array(repeating: 3, count: Int(seconds * 16_000)) }
    private static func voice(_ seconds: Double) -> [Int16] {
        (0..<Int(seconds * 16_000)).map { Int16(8_000 * sin(Double($0) * 2 * .pi * 220 / 16_000)) }
    }

    @Test func endsASentenceAfterItsPause() {
        var detector = SpeechEndDetector()
        let heard = [Self.quiet(1), Self.voice(1), Self.quiet(0.4), Self.quiet(0.3), Self.quiet(2)]
            .map { detector.hearsEnd(in: $0) }
        #expect(heard == [false, false, false, true, false])
    }

    @Test func ignoresAClickTooShortToBeSpeech() {
        var detector = SpeechEndDetector()
        _ = detector.hearsEnd(in: Self.quiet(1))
        let ended = detector.hearsEnd(in: Self.voice(0.1) + Self.quiet(1))
        #expect(!ended)
    }
}
