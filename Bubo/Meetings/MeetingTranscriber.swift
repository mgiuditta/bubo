import AVFoundation
import os
import Speech

/// Transcribes a Riunione's track on the Mac with `SpeechAnalyzer` and `SpeechTranscriber`, in the main language of
/// the Riunioni.
///
/// Nothing goes to the network but the one-time download of the language model.
nonisolated enum MeetingTranscriber {
    /// The sentences of the track at `url`, said by `speaker` (`nil` when unknown), with their time from the start.
    ///
    /// - Throws: ``MeetingFailure/languageUnsupported`` for a language without a model;
    ///   ``MeetingFailure/transcriptionFailed`` when the file cannot be read or the analysis stops.
    static func transcribe(_ url: URL, as speaker: MeetingLine.Speaker?) async throws(MeetingFailure) -> [MeetingLine] {
        let transcriber = try await transcriber()
        do {
            let file = try AVAudioFile(forReading: url)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            // Reading before the analysis starts, so no result goes by unread.
            let reading = Task {
                var lines: [MeetingLine] = []
                for try await result in transcriber.results where result.isFinal {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    lines.append(MeetingLine(speaker: speaker, start: .seconds(result.range.start.seconds), text: text,
                                             duration: .seconds(result.range.duration.seconds)))
                }
                return lines
            }
            if let end = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return try await reading.value
        } catch {
            Logger.meetings.error("Track not transcribed: \(String(describing: error), privacy: .public)")
            throw .transcriptionFailed
        }
    }

    /// The transcriber of the main language of the Riunioni, its model downloaded first if needed.
    private static func transcriber() async throws(MeetingFailure) -> SpeechTranscriber {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: MeetingLanguage.saved()) else {
            throw .languageUnsupported
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            Logger.meetings.error("Speech model not installed: \(String(describing: error), privacy: .public)")
            throw .languageUnsupported
        }
        return transcriber
    }
}
