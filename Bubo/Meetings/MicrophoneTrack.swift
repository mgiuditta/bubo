import AVFoundation
import os

/// Writes the microphone to a file, as one mono track: the user's side of the Riunione.
final class MicrophoneTrack {
    private var engine: AVAudioEngine?

    /// Creates the track, with the microphone closed.
    init() {}

    /// Opens the microphone and starts writing it to an AAC file at `url`.
    ///
    /// - Throws: ``MeetingFailure/microphoneUnavailable`` when there is no microphone or it does not start.
    func start(writingTo url: URL) throws(MeetingFailure) {
        let engine = AVAudioEngine()
        let microphone = engine.inputNode.outputFormat(forBus: 0)
        guard microphone.channelCount > 0, microphone.sampleRate > 0,
              let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: microphone.sampleRate,
                                       channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: microphone, to: mono) else { throw .microphoneUnavailable }
        // A microphone with more channels is mixed down, not cut to the first.
        converter.downmix = true
        do {
            let file = try AVAudioFile(forWriting: url, settings: MeetingAudioFormat.settings(for: mono),
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: microphone,
                                        block: Self.writer(converting: converter, into: file))
            engine.prepare()
            try engine.start()
        } catch {
            Logger.meetings.error("Microphone not started: \(error)")
            engine.inputNode.removeTap(onBus: 0)
            throw .microphoneUnavailable
        }
        self.engine = engine
    }

    /// Closes the microphone, which turns the orange dot off, and the file.
    func stop() {
        // Removing the tap releases the block, which closes the file.
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    /// The tap on the microphone, run on the audio thread: it writes each buffer to `file`, mixed down to mono.
    nonisolated private static func writer(converting converter: AVAudioConverter,
                                           into file: AVAudioFile) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let converted = SpeechListener.convert(buffer, with: converter) else { return }
            do {
                try file.write(from: converted)
            } catch {
                Logger.meetings.error("Microphone buffer not written: \(error)")
            }
        }
    }
}
