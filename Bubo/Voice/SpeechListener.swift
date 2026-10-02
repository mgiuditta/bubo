import AVFoundation
import OSLog
import Speech

/// Hears the microphone with an `AVAudioEngine` and transcribes it on the Mac with `SpeechAnalyzer` and
/// `SpeechTranscriber`, in the language of the Mac: nothing goes to the network but the one-time model download.
///
/// The microphone is open only between `start` and `finish` or `cancel`, so the orange dot is on only meanwhile.
final class SpeechListener: VoiceListener {
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    /// Reads the transcriber's results, and returns the finalized text once the analyzer finishes.
    private var reading: Task<String, Never>?
    private var metering: Task<Void, Never>?

    /// Creates a listener with the microphone closed.
    init() {}

    func start(partial: @escaping (String) -> Void, level: @escaping (Float) -> Void) async throws(VoiceFailure) {
        let transcriber = try await Self.transcriber()
        // A buffer in another format gives no error and no text: the format always comes from the analyzer.
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw .languageUnsupported
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let engine = AVAudioEngine()
        let microphone = engine.inputNode.outputFormat(forBus: 0)
        guard microphone.channelCount > 0, microphone.sampleRate > 0,
              let converter = AVAudioConverter(from: microphone, to: format) else { throw .microphoneUnavailable }
        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let (levels, levelInput) = AsyncStream.makeStream(of: Float.self, bufferingPolicy: .bufferingNewest(1))
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: microphone,
                                    block: Self.tap(converting: converter, into: input, levels: levelInput))
        // Reading before the analyzer starts, so no result goes by unread.
        let reading = Task {
            var finalized = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalized += text
                        partial(finalized)
                    } else {
                        partial(finalized + text)
                    }
                }
            } catch {
                Logger.voice.error("Transcription stopped: \(String(describing: error), privacy: .public)")
            }
            return finalized
        }
        do {
            try await analyzer.prepareToAnalyze(in: format)
            engine.prepare()
            try engine.start()
            try await analyzer.start(inputSequence: stream)
        } catch {
            Logger.voice.error("Listening not started: \(String(describing: error), privacy: .public)")
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            input.finish()
            levelInput.finish()
            await analyzer.cancelAndFinishNow()
            reading.cancel()
            throw .microphoneUnavailable
        }
        self.engine = engine
        self.analyzer = analyzer
        self.input = input
        self.reading = reading
        metering = Task {
            for await value in levels { level(value) }
        }
    }

    func finish() async -> String {
        closeMicrophone()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            Logger.voice.error("Transcription not finalized: \(String(describing: error), privacy: .public)")
            await analyzer?.cancelAndFinishNow()
        }
        let text = await reading?.value ?? ""
        reset()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() async {
        closeMicrophone()
        await analyzer?.cancelAndFinishNow()
        reading?.cancel()
        reset()
    }

    /// Stops the engine, which turns the orange dot off, and ends the audio the analyzer gets.
    private func closeMicrophone() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        input?.finish()
        metering?.cancel()
    }

    private func reset() {
        engine = nil
        analyzer = nil
        input = nil
        reading = nil
        metering = nil
    }

    /// The transcriber of the Mac's language, with its model installed.
    ///
    /// - Throws: `languageUnsupported` for a language it does not know; `modelDownloading` while the model downloads,
    ///   which starts here the first time; `modelUnavailable` when the download could not start.
    private static func transcriber() async throws(VoiceFailure) -> SpeechTranscriber {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw .languageUnsupported
        }
        // Volatile results stream only with fast results: without them the text comes at the pauses (spec 08, misura B).
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return transcriber
        case .unsupported:
            throw .languageUnsupported
        case .downloading:
            throw .modelDownloading
        case .supported:
            do {
                guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                    return transcriber
                }
                Task {
                    do {
                        try await request.downloadAndInstall()
                    } catch {
                        Logger.voice.error("Speech model not downloaded: \(String(describing: error), privacy: .public)")
                    }
                }
                throw VoiceFailure.modelDownloading
            } catch let failure as VoiceFailure {
                throw failure
            } catch {
                Logger.voice.error("Speech model not requested: \(String(describing: error), privacy: .public)")
                throw .modelUnavailable
            }
        @unknown default:
            throw .languageUnsupported
        }
    }

    /// The tap on the microphone, run on the audio thread: it measures the level and hands the analyzer the buffer in
    /// its format.
    nonisolated private static func tap(converting converter: AVAudioConverter,
                                        into input: AsyncStream<AnalyzerInput>.Continuation,
                                        levels: AsyncStream<Float>.Continuation) -> AVAudioNodeTapBlock {
        { buffer, _ in
            levels.yield(level(of: buffer))
            guard let converted = convert(buffer, with: converter) else { return }
            input.yield(AnalyzerInput(buffer: converted))
        }
    }

    /// The buffer in the converter's output format, or `nil` when it cannot be converted.
    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return nil }
        // The converter calls the block on this thread, before `convert` returns.
        nonisolated(unsafe) let source = buffer
        nonisolated(unsafe) var isConsumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            if isConsumed {
                status.pointee = .noDataNow
                return nil
            }
            isConsumed = true
            status.pointee = .haveData
            return source
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    /// The root mean square of the first channel, scaled so that speech near the microphone reaches about 1.
    nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        return min(1, (sum / Float(count)).squareRoot() * 8)
    }
}
