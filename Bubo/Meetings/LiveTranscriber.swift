import AVFoundation
import os
import Speech

/// Transcribes one track of a Riunione while it is recorded, for the Suggeritore: the track hands it each buffer it
/// writes, and each finished sentence comes back as a ``MeetingLine``. On the Mac, as the trascrizione after the Riunione.
final class LiveTranscriber {
    /// Whose track it hears.
    let speaker: MeetingLine.Speaker
    private var analyzer: SpeechAnalyzer?
    private var format: AVAudioFormat?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var reading: Task<Void, Never>?

    /// Creates the transcriber of `speaker`'s track, not started.
    init(speaker: MeetingLine.Speaker) {
        self.speaker = speaker
    }

    /// Starts the analysis; each finished sentence reaches `hear`, on the main actor.
    ///
    /// - Throws: ``MeetingFailure/languageUnsupported`` without a model for the language of the Riunioni;
    ///   ``MeetingFailure/transcriptionFailed`` when the analyzer does not start.
    func start(hearing hear: @escaping (MeetingLine) -> Void) async throws(MeetingFailure) {
        let transcriber = try await MeetingTranscriber.transcriber(isLive: true)
        // A buffer in another format gives no error and no text: the format always comes from the analyzer.
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw .languageUnsupported
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let speaker = speaker
        // Reading before the analyzer starts, so no result goes by unread.
        reading = Task {
            do {
                for try await result in transcriber.results where result.isFinal {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    hear(MeetingLine(speaker: speaker, start: .seconds(result.range.start.seconds), text: text,
                                     length: .seconds(result.range.duration.seconds)))
                }
            } catch {
                Logger.meetings.error("Live transcription stopped: \(String(describing: error), privacy: .public)")
            }
        }
        do {
            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: stream)
        } catch {
            Logger.meetings.error("Live transcription not started: \(String(describing: error), privacy: .public)")
            input.finish()
            await analyzer.cancelAndFinishNow()
            reading?.cancel()
            reading = nil
            throw .transcriptionFailed
        }
        self.analyzer = analyzer
        self.format = format
        self.input = input
    }

    /// The block a track calls on its audio thread with each buffer in `source`'s format; `nil` when not started or
    /// when that format cannot be converted.
    func feed(from source: AVAudioFormat) -> (@Sendable (AVAudioPCMBuffer) -> Void)? {
        guard let format, let input, let converter = AVAudioConverter(from: source, to: format) else { return nil }
        return Self.feeder(converting: converter, into: input)
    }

    /// Ends the analysis; the buffers that still arrive are dropped.
    func stop() async {
        input?.finish()
        await analyzer?.cancelAndFinishNow()
        reading?.cancel()
        analyzer = nil
        format = nil
        input = nil
        reading = nil
    }

    /// Converts each buffer to the analyzer's format and hands it over, on the track's audio thread.
    nonisolated private static func feeder(converting converter: AVAudioConverter,
                                           into input: AsyncStream<AnalyzerInput>.Continuation)
        -> @Sendable (AVAudioPCMBuffer) -> Void {
        return { buffer in
            guard let converted = SpeechListener.convert(buffer, with: converter) else { return }
            input.yield(AnalyzerInput(buffer: converted))
        }
    }
}
