import Foundation
import Observation
import os

/// A Domanda that ended, kept so it shows among the Conversazioni and can be continued.
nonisolated struct ArchivedQuestion: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    /// The first prompt, shortened.
    var title: String
    /// When the Domanda was last archived.
    var date: Date
    var turns: [QuestionTurn]
    /// The Sessione this Domanda became, if it did.
    var sessionID: UUID?
}

/// The Domande that ended, in a JSON file in Bubo's Application Support folder (ADR 0006: Bubo keeps the
/// conversations).
@Observable
final class QuestionArchive {
    /// The Domande, newest first.
    private(set) var questions: [ArchivedQuestion]
    @ObservationIgnored private let file: URL

    /// Reads the archive at `file`; a missing or unreadable file is an empty archive.
    init(file: URL) {
        self.file = file
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([ArchivedQuestion].self, from: $0) }
        questions = (saved ?? []).sorted { $0.date > $1.date }
    }

    /// The archive in Bubo's Application Support folder.
    static func live() throws -> QuestionArchive {
        let folder = URL.applicationSupportDirectory.appending(path: "Bubo", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return QuestionArchive(file: folder.appending(path: "Domande.json"))
    }

    /// Keeps `question`, replacing the one with its id.
    func save(_ question: ArchivedQuestion) {
        questions.removeAll { $0.id == question.id }
        questions.append(question)
        questions.sort { $0.date > $1.date }
        write()
    }

    /// Records that the Domanda `question` became the Sessione `session`.
    func linkSession(_ session: UUID, toQuestion question: UUID) {
        guard let index = questions.firstIndex(where: { $0.id == question }) else { return }
        questions[index].sessionID = session
        write()
    }

    private func write() {
        do {
            try JSONEncoder().encode(questions).write(to: file, options: .atomic)
        } catch {
            Logger(subsystem: "com.mgiuditta.bubo", category: "questions").error("Domande not saved: \(error)")
        }
    }
}
