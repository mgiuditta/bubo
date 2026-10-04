import Foundation
import Testing
@testable import Bubo

/// The Domande that ended, kept on disk so they show among the Conversazioni.
@MainActor
struct QuestionArchiveTests {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "domande-\(UUID().uuidString).json")
    }

    @Test func aSavedQuestionIsReadBackNewestFirst() {
        let file = file()
        let archive = QuestionArchive(file: file)
        archive.save(ArchivedQuestion(id: UUID(), title: "Meteo", date: .distantPast,
                                      turns: [QuestionTurn(prompt: "Meteo", answer: "Sole")], sessionID: nil))
        archive.save(ArchivedQuestion(id: UUID(), title: "Treni", date: .now,
                                      turns: [QuestionTurn(prompt: "Treni", answer: "18:02")], sessionID: nil))
        #expect(QuestionArchive(file: file).questions.map(\.title) == ["Treni", "Meteo"])
    }

    @Test func savingTheSameQuestionAgainReplacesIt() {
        let archive = QuestionArchive(file: file())
        var question = ArchivedQuestion(id: UUID(), title: "Meteo", date: .now,
                                        turns: [QuestionTurn(prompt: "Meteo", answer: "Sole")], sessionID: nil)
        archive.save(question)
        question.turns.append(QuestionTurn(prompt: "E domani?", answer: "Pioggia"))
        archive.save(question)
        #expect(archive.questions.count == 1)
        #expect(archive.questions.first?.turns.count == 2)
    }

    @Test func aSessionBornFromAQuestionIsLinked() {
        let archive = QuestionArchive(file: file())
        let id = UUID()
        archive.save(ArchivedQuestion(id: id, title: "Login", date: .now, turns: [], sessionID: nil))
        let session = UUID()
        archive.linkSession(session, toQuestion: id)
        #expect(archive.questions.first?.sessionID == session)
    }

    @Test func aMissingOrBrokenFileIsAnEmptyArchive() throws {
        let file = file()
        #expect(QuestionArchive(file: file).questions.isEmpty)
        try Data("nope".utf8).write(to: file)
        #expect(QuestionArchive(file: file).questions.isEmpty)
    }

    @Test func aNewQuestionArchivesTheOneThatEnded() {
        let archive = QuestionArchive(file: file())
        let model = QuestionModel()
        model.archive = archive
        let id = UUID()
        model.continueQuestion(ArchivedQuestion(id: id, title: "Che tempo fa?", date: .distantPast,
                                                turns: [QuestionTurn(prompt: "Che tempo fa?", answer: "Sole")],
                                                sessionID: nil))
        #expect(model.currentQuestionID == id)
        model.startNewQuestion()
        #expect(archive.questions.map(\.id) == [id])
        #expect(archive.questions.first?.title == "Che tempo fa?")
        #expect(model.currentQuestionID != id)
    }

    @Test func aContinuedQuestionKeepsItsTurns() {
        let model = QuestionModel()
        let turns = [QuestionTurn(prompt: "Meteo", answer: "Sole")]
        model.continueQuestion(ArchivedQuestion(id: UUID(), title: "Meteo", date: .now, turns: turns, sessionID: nil))
        #expect(model.turns == turns)
    }

    @Test func anEmptyQuestionIsNotArchived() {
        let archive = QuestionArchive(file: file())
        let model = QuestionModel()
        model.archive = archive
        model.startNewQuestion()
        #expect(archive.questions.isEmpty)
    }

    @Test func aQuestionTurnedIntoASessionStaysListedAsItsOrigin() {
        let archive = QuestionArchive(file: file())
        let model = QuestionModel()
        model.archive = archive
        let id = UUID()
        model.continueQuestion(ArchivedQuestion(id: id, title: "Login", date: .distantPast,
                                                turns: [QuestionTurn(prompt: "Login", answer: "Scade il token")],
                                                sessionID: nil))
        let draft = model.turnIntoSession()
        #expect(draft.originQuestion == id)
        #expect(archive.questions.map(\.id) == [id])
    }
}
