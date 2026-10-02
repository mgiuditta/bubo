/// Says the Sintesi parlata aloud (spec 08, `Voice/SpeechOutput`).
protocol VoiceSpeaker: AnyObject {
    /// Whether the Mac has only basic-quality voices in its language, and Bubo speaks with one of them.
    var hasOnlyDefaultVoices: Bool { get }
    /// Says `text`, and returns once it is heard to the end, or at once when the task is cancelled.
    ///
    /// - Parameter level: Gets the level of the voice being heard, from 0 to 1, a few times a second; its first call
    ///   is the first audio.
    func speak(_ text: String, level: @escaping (Float) -> Void) async
}
