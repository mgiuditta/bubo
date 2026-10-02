import AppIntents
import Foundation
import Synchronization
import Testing
@testable import Bubo

@MainActor
@Suite(.serialized)
struct AskBuboIntentTests {
    /// Records what "Chiedi a Bubo" asks, in place of the Domanda of the HUD.
    @MainActor final class RecordingQuestions: QuestionAsking {
        private(set) var asked: [(text: String, attachments: [Allegato])] = []

        func ask(_ text: String, attachments: [Allegato]) {
            asked.append((text, attachments))
        }
    }

    let questions = RecordingQuestions()

    init() {
        AskBuboIntent.questions = questions
    }

    func intent(_ text: String, files: [IntentFile] = []) -> AskBuboIntent {
        let intent = AskBuboIntent()
        intent.text = text
        intent.files = files
        return intent
    }

    @Test func theTextAndTheFilesBecomeADomanda() async throws {
        let notes = IntentFile(data: Data("Comprare il pane".utf8), filename: "note.txt", type: .plainText)
        _ = try await intent("  Riassumi  ", files: [notes]).perform()

        let asked = try #require(questions.asked.first)
        #expect(questions.asked.count == 1)
        #expect(asked.text == "Riassumi")
        #expect(asked.attachments == [Allegato(name: "note.txt", text: "Comprare il pane")])
    }

    @Test func aBlankTextAsksNothing() async {
        await #expect(throws: (any Error).self) {
            _ = try await intent(" \n ").perform()
        }
        #expect(questions.asked.isEmpty)
    }

    @Test func aFileThatIsNotTextAsksNothing() async {
        let image = IntentFile(data: Data([0xFF, 0xD8, 0xFF, 0xE0, 0xC3]), filename: "foto.jpg", type: .jpeg)
        await #expect(throws: AskBuboError.self) {
            _ = try await intent("Che cos'è?", files: [image]).perform()
        }
        #expect(questions.asked.isEmpty)
    }
}

@MainActor
struct QuestionModelAttachmentsTests {
    /// Answers on the Mac, keeping the Allegati it was given.
    nonisolated final class RecordingAnswerer: OnDeviceAnswering, Sendable {
        let received = Mutex<[Allegato]>([])

        func answer(to question: String, attachments: [Allegato]) -> AsyncThrowingStream<String, any Error> {
            received.withLock { $0 = attachments }
            return AsyncThrowingStream { continuation in
                continuation.yield("Pane.")
                continuation.finish()
            }
        }
    }

    @Test func theAllegatiReachTheModelThatAnswers() async throws {
        let answerer = RecordingAnswerer()
        let model = try QuestionModelTests.routedModel(.shortFact, onDevice: .fitting, answerer: answerer)
        let notes = Allegato(name: "note.txt", text: "Comprare il pane")
        model.ask("Che cosa devo comprare?", attachments: [notes])
        await model.answering?.value

        #expect(model.answer == "Pane.")
        #expect(answerer.received.withLock { $0 } == [notes])
        // The endpoints receive the text alone: none is offered for a Domanda with Allegati.
        #expect(model.retryAlternatives.allSatisfy { if case .claude = $0.target { true } else { false } })
    }
}
