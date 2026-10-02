/// Hears the microphone and turns it into text on the Mac (spec 08, `Voice/Transcriber`).
protocol VoiceListener: AnyObject {
    /// Opens the microphone and starts transcribing.
    ///
    /// - Parameters:
    ///   - partial: Gets the whole text heard so far, each time it changes.
    ///   - level: Gets the microphone level, from 0 to 1, a few times a second.
    func start(partial: @escaping (String) -> Void, level: @escaping (Float) -> Void) async throws(VoiceFailure)
    /// Closes the microphone and returns the final text of what was heard.
    func finish() async -> String
    /// Closes the microphone and drops what was heard.
    func cancel() async
}
