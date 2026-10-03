import AppIntents

/// "Registra una Riunione", from Siri, Spotlight and Comandi rapidi: brings Bubo forward on the window of the
/// Riunioni, where the user picks the app and confirms the participants were told. It never starts recording alone.
struct RecordMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Registra una Riunione"
    static let description = IntentDescription("Apre la finestra di Bubo per registrare una Riunione e salvarla nel Secondo cervello.")
    /// The window opens only with Bubo in front.
    static let supportedModes: IntentModes = .foreground(.immediate)

    /// The recorder whose window opens, set at launch before any intent runs.
    @MainActor static var recorder: MeetingRecorder?

    func perform() async throws -> some IntentResult {
        try await Self.open()
        return .result()
    }

    /// Opens the window of `recorder`.
    ///
    /// - Throws: `SearchHistoryError.notReady` before launch set `recorder`.
    @MainActor private static func open() throws {
        guard let recorder else { throw SearchHistoryError.notReady }
        recorder.showWindow()
    }
}
