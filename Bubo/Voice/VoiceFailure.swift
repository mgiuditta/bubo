/// Why push-to-talk could not listen.
nonisolated enum VoiceFailure: Error, Equatable {
    /// The user denied Bubo the microphone in System Settings.
    case microphoneDenied
    /// The Mac has no microphone, or it could not be opened.
    case microphoneUnavailable
    /// The language of the Mac is not one the on-device transcription knows.
    case languageUnsupported
    /// The on-device model of the language is downloading; it is ready in a while.
    case modelDownloading
    /// The on-device model of the language is missing and could not be downloaded, usually for lack of network.
    case modelUnavailable
}
