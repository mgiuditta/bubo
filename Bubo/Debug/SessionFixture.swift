#if DEBUG
import Foundation

/// Fake Sessioni for the UI tests, used instead of the user's with the launch argument `-sessions.fixture YES`.
///
/// Only in Debug: a Release build ignores the argument.
enum SessionFixture {
    /// The defaults key the launch argument sets.
    static let defaultsKey = "sessions.fixture"

    /// Whether the launch asked for the fake Sessioni.
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    /// Creates a temporary folder laid out as Bubo's Application Support, holding one Sessione, «Login che scade»,
    /// in the Progetto «bubo».
    ///
    /// - Returns: The folder, to read `Bubo/Sessioni.json` from.
    static func makeSupportFolder() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "BuboSessionFixture-\(UUID().uuidString)",
                                                    directoryHint: .isDirectory)
        // A real folder: a Progetto that is gone puts its Sessione in Errore.
        let project = root.appending(path: "bubo", directoryHint: .isDirectory)
        let bubo = root.appending(path: "Bubo", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bubo, withIntermediateDirectories: true)
        let session = Session(id: UUID(), title: "Login che scade", project: project, activity: .ferma,
                              activitySince: .now)
        try JSONEncoder().encode([session]).write(to: bubo.appending(path: "Sessioni.json"))
        return root
    }

    /// Creates an archive in a temporary folder holding one answered Domanda, «Come funziona il router?».
    ///
    /// - Returns: The archive, in place of the user's Domande.
    static func makeQuestionArchive() throws -> QuestionArchive {
        let folder = URL.temporaryDirectory.appending(path: "BuboQuestionFixture-\(UUID().uuidString)",
                                                      directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Domande.json")
        let turn = QuestionTurn(prompt: "Come funziona il router?",
                                answer: "Il router sceglie il modello per ogni richiesta: prima la Categoria, poi il costo e la Quota rimasta.")
        let question = ArchivedQuestion(id: UUID(), title: "Come funziona il router?", date: .now, turns: [turn])
        try JSONEncoder().encode([question]).write(to: file)
        return QuestionArchive(file: file)
    }
}
#endif
