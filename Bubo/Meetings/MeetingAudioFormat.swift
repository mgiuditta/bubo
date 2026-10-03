import AVFoundation

/// The format of a Riunione's tracks on disk: AAC, a tenth of the space of the raw samples.
nonisolated enum MeetingAudioFormat {
    /// The settings of an AAC file with the rate and channels of `format`.
    static func settings(for format: AVAudioFormat) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 64_000,
        ]
    }
}
