import AVFoundation
import OSLog

/// Says the Sintesi parlata with the voices of the Mac: `AVSpeechSynthesizer` writes the audio and an
/// `AVAudioPlayerNode` plays it, so nothing goes to the network.
///
/// The engine is the output's only: the microphone stays closed while Bubo speaks, and the orange dot with it. The voice
/// processing for the echo comes with the barge-in by voice, once its spike passes (spec 08).
///
/// While it plays, Esc stops it from any app: the panel never takes the keyboard, so Esc is a global shortcut taken
/// from the app in front only for as long as Bubo speaks.
final class SpeechOutput: VoiceSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// The format the player is connected with; `nil` before the first buffer.
    private var connectedFormat: AVAudioFormat?
    /// Counts the utterances and the stops, so that the end of an interrupted one does not stop the next.
    private var utterances = 0
    /// The buffers of the utterance playing, ended by a stop.
    private var buffers: AsyncStream<AVAudioPCMBuffer>.Continuation?
    /// Esc, registered only while the voice plays.
    private lazy var escape = GlobalHotKey { [weak self] in self?.stop() }

    /// Creates the output, silent until the first `speak`.
    init() {
        engine.attach(player)
    }

    var hasOnlyDefaultVoices: Bool {
        Self.voice()?.quality ?? .default == .default
    }

    func speak(_ text: String, level: @escaping (Float) -> Void) async {
        stop()
        let utterance = utterances
        let spoken = AVSpeechUtterance(string: text)
        spoken.voice = Self.voice()
        let (buffers, input) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        self.buffers = input
        let (levels, levelInput) = AsyncStream.makeStream(of: Float.self, bufferingPolicy: .bufferingNewest(1))
        let metering = Task {
            for await value in levels { level(value) }
        }
        defer {
            metering.cancel()
            levelInput.finish()
            if utterance == utterances { silence() }
        }
        synthesizer.write(spoken, toBufferCallback: Self.collect(into: input))
        await withTaskCancellationHandler {
            await play(buffers, of: utterance, levels: levelInput)
        } onCancel: {
            input.finish()
            Task { @MainActor in
                if utterance == self.utterances { self.stop() }
            }
        }
    }

    /// Plays the buffers of `utterance` as they come, and returns once the last one is heard or the voice is stopped.
    private func play(_ buffers: AsyncStream<AVAudioPCMBuffer>, of utterance: Int,
                      levels: AsyncStream<Float>.Continuation) async {
        var format: AVAudioFormat?
        for await buffer in buffers {
            // Stopped: the buffers already written are left unplayed.
            guard utterance == utterances else { return }
            if format == nil {
                guard start(with: buffer.format, levels: levels) else { return }
                format = buffer.format
            }
            schedule(buffer)
        }
        guard utterance == utterances, !Task.isCancelled, let format, let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) else {
            return
        }
        // A frame of silence after the last buffer: when it is played back, the voice is heard to the end.
        silence.frameLength = 1
        _ = await player.scheduleBuffer(silence, completionCallbackType: .dataPlayedBack)
    }

    /// Queues `buffer` after the ones already playing.
    private func schedule(_ buffer: AVAudioPCMBuffer) {
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Connects the player in `format`, starts the engine and measures what it plays; `false` when it cannot start.
    private func start(with format: AVAudioFormat, levels: AsyncStream<Float>.Continuation) -> Bool {
        if connectedFormat != format {
            engine.connect(player, to: engine.mainMixerNode, format: format)
            connectedFormat = format
        }
        player.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.meter(into: levels))
        do {
            engine.prepare()
            try engine.start()
        } catch {
            Logger.voice.error("Speech not played: \(String(describing: error), privacy: .public)")
            player.removeTap(onBus: 0)
            return false
        }
        player.play()
        do {
            try escape.register(.escape)
        } catch {
            Logger.voice.notice("Esc not taken while speaking: \(String(describing: error), privacy: .public)")
        }
        return true
    }

    func stop() {
        utterances += 1
        guard buffers != nil else { return }
        let interval = Signposts.beginInterval(.voiceInterruption)
        silence()
        Signposts.endInterval(.voiceInterruption, interval)
    }

    /// Stops the voice and the engine, and gives Esc back to the app in front.
    private func silence() {
        buffers?.finish()
        buffers = nil
        escape.unregister()
        synthesizer.stopSpeaking(at: .immediate)
        player.stop()
        player.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
    }

    /// The best voice of the Mac's language: an enhanced or premium one when the user downloaded it, otherwise the
    /// system's for the language.
    nonisolated static func voice(for locale: Locale = .current) -> AVSpeechSynthesisVoice? {
        let language = locale.language.languageCode?.identifier
        let region = locale.region?.identifier
        let better = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            let voiceLocale = Locale(identifier: voice.language)
            return voiceLocale.language.languageCode?.identifier == language && voice.quality != .default
        }
        // Higher quality first, then the Mac's region.
        let best = better.max { first, second in
            (first.quality.rawValue, Locale(identifier: first.language).region?.identifier == region ? 1 : 0)
                < (second.quality.rawValue, Locale(identifier: second.language).region?.identifier == region ? 1 : 0)
        }
        return best ?? AVSpeechSynthesisVoice(language: locale.identifier(.bcp47))
            ?? language.flatMap(AVSpeechSynthesisVoice.init(language:))
    }

    /// The synthesizer's callback, run off the main thread: it hands on the buffers, in the format the player plays, and
    /// ends at the empty one.
    nonisolated private static func collect(into input: AsyncStream<AVAudioPCMBuffer>.Continuation)
        -> AVSpeechSynthesizer.BufferCallback {
        { buffer in
            guard let buffer = buffer as? AVAudioPCMBuffer, buffer.frameLength > 0 else {
                input.finish()
                return
            }
            guard let playable = playable(buffer) else { return }
            // A new buffer, which nothing here touches again: it goes to the player alone.
            nonisolated(unsafe) let copy = playable
            input.yield(copy)
        }
    }

    /// The tap on the player, run on the audio thread: the level of what is being heard.
    nonisolated private static func meter(into levels: AsyncStream<Float>.Continuation) -> AVAudioNodeTapBlock {
        { buffer, _ in levels.yield(SpeechListener.level(of: buffer)) }
    }

    /// A copy of `buffer` in 32-bit float, which the player plays: the synthesizer can write 16-bit integers, and it
    /// reuses its buffers.
    nonisolated private static func playable(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: buffer.format.sampleRate,
                                         channels: buffer.format.channelCount),
              let converter = AVAudioConverter(from: buffer.format, to: format),
              let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength)
        else { return nil }
        do {
            try converter.convert(to: converted, from: buffer)
        } catch {
            Logger.voice.error("Speech not converted: \(String(describing: error), privacy: .public)")
            return nil
        }
        return converted
    }
}
