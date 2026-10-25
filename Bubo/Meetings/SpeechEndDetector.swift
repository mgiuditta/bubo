import Foundation

/// Tells when someone stopped talking in a track of 16 kHz samples: after ``silence`` of quiet that follows at least
/// ``minimumSpeech`` of voice. The Suggeritore closes the sentence there instead of waiting for the transcriber, which
/// takes seconds more to decide by itself.
///
/// Voice is energy above the background noise, which it learns from the quiet frames.
nonisolated struct SpeechEndDetector: Sendable {
    // ponytail: energy only; a trained voice detector if coughs and keyboards close sentences too often.
    private var floor = Self.minimumLevel / Self.ratio
    private var pending: [Int16] = []
    private var isSpeaking = false
    private var voicedFrames = 0
    private var quietFrames = 0

    /// Creates a detector that heard nothing yet.
    init() {}

    /// Hears `samples`; `true` when a sentence ended among them.
    mutating func hearsEnd(in samples: some Collection<Int16>) -> Bool {
        pending += samples
        var ended = false
        while pending.count >= Self.frame {
            let level = Self.level(of: pending.prefix(Self.frame))
            pending.removeFirst(Self.frame)
            let isVoice = level > max(Self.minimumLevel, floor * Self.ratio)
            if !isVoice { floor = 0.95 * floor + 0.05 * level }
            if isVoice {
                isSpeaking = true
                voicedFrames += 1
                quietFrames = 0
            } else if isSpeaking {
                quietFrames += 1
                if quietFrames >= Self.silenceFrames {
                    ended = ended || voicedFrames >= Self.minimumSpeechFrames
                    isSpeaking = false
                    voicedFrames = 0
                    quietFrames = 0
                }
            }
        }
        return ended
    }

    /// The root mean square of `frame`, from 0 to 1.
    private static func level(of frame: some Collection<Int16>) -> Float {
        let sum = frame.reduce(Float.zero) { $0 + Float($1) * Float($1) }
        return (sum / Float(frame.count)).squareRoot() / Float(Int16.max)
    }

    /// 30 ms at 16 kHz.
    static let frame = 480
    /// The quiet that ends a sentence: 0.6 s, as `sbu-live` did.
    static let silence: TimeInterval = 0.6
    /// Less voice than this is noise, not a sentence.
    static let minimumSpeech: TimeInterval = 0.25
    /// Below this level it is always quiet.
    static let minimumLevel: Float = 0.004
    /// Voice is this many times louder than the background.
    static let ratio: Float = 3

    private static let silenceFrames = Int(silence * 16_000) / frame
    private static let minimumSpeechFrames = Int(minimumSpeech * 16_000) / frame
}
