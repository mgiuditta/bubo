import Foundation
import Testing
@testable import Bubo

struct AgentQuestionTests {
    static let question = AgentQuestion(id: "q1", items: [
        .init(question: "Quale libreria?", header: "Libreria",
              options: [.init(label: "date-fns", detail: "Leggera"), .init(label: "Luxon")], allowsMultiple: false),
        .init(question: "Cosa abilito?", header: "Funzioni",
              options: [.init(label: "Cache"), .init(label: "Log")], allowsMultiple: true),
    ])

    @Test func theQuestionEventDecodes() throws {
        let line = #"""
            {"v":4,"type":"question","id":"a1","request":"q1","questions":[
            {"question":"Quale libreria?","header":"Libreria","multiSelect":false,
             "options":[{"label":"date-fns","description":"Leggera"},{"label":"Luxon"}]},
            {"question":"Cosa abilito?","header":"Funzioni","multiSelect":true,
             "options":[{"label":"Cache"},{"label":"Log"}]}]}
            """#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == .question(id: "a1", Self.question))
    }

    @Test func theAnswerCarriesTheChosenOptionsAndTheWrittenText() throws {
        let replies = [AgentQuestion.Reply(options: [1]), AgentQuestion.Reply(options: [0, 1], text: "  Tracce ")]
        let line = try BridgeCommand.answerQuestion(request: "q1", replies: replies).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"answers":[{"options":[1]},{"options":[0,1],"text":"Tracce"}],"request":"q1","type":"question","v":4}"# + "\n")
    }

    @Test func notAnsweringCarriesNoAnswers() throws {
        let line = try BridgeCommand.answerQuestion(request: "q1", replies: nil).line()
        #expect(String(decoding: line, as: UTF8.self) == #"{"request":"q1","type":"question","v":4}"# + "\n")
    }

    @Test(arguments: [
        ([AgentQuestion.Reply(options: [0]), AgentQuestion.Reply(options: [1])], true),
        ([AgentQuestion.Reply(text: "Temporal"), AgentQuestion.Reply(options: [0, 1])], true),
        ([AgentQuestion.Reply(options: [0]), AgentQuestion.Reply(text: "Tracce")], true),
        ([AgentQuestion.Reply(options: [0, 1]), AgentQuestion.Reply(options: [0])], false),
        ([AgentQuestion.Reply(), AgentQuestion.Reply(options: [0])], false),
        ([AgentQuestion.Reply(options: [0]), AgentQuestion.Reply(text: "   ")], false),
        ([AgentQuestion.Reply(options: [0])], false),
    ])
    func everyQuestionNeedsAnAnswer(replies: [AgentQuestion.Reply], isAnswered: Bool) {
        #expect(Self.question.isAnswered(by: replies) == isAnswered)
    }

    @Test func aCopilotQuestionDecodesAsOneQuestionWithItsChoices() throws {
        let line = #"""
            {"v":4,"type":"question","id":"c1","request":"q2","questions":[
            {"question":"Quale libreria?","header":"","multiSelect":false,"options":[{"label":"Zod"},{"label":"Valibot"}]}]}
            """#
        let event = try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8))
        #expect(event == .question(id: "c1", AgentQuestion(id: "q2", items: [
            .init(question: "Quale libreria?", header: "", options: [.init(label: "Zod"), .init(label: "Valibot")],
                  allowsMultiple: false),
        ])))
    }

    @Test func aCopilotQuestionWithoutChoicesTakesOnlyAWrittenAnswer() throws {
        let line = #"""
            {"v":4,"type":"question","id":"c1","request":"q3","questions":[
            {"question":"Chi sei?","header":"","multiSelect":false,"options":[]}]}
            """#
        guard case let .question(_, question) = try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) else {
            Issue.record("Not a question")
            return
        }
        #expect(question.items.first?.allowsText == true)
        #expect(question.isAnswered(by: [.init(text: "Un gufo")]))
        #expect(!question.isAnswered(by: [.init()]))
    }

    @Test func aCopilotQuestionThatRulesOutWrittenAnswersNeedsAChoice() throws {
        let line = #"""
            {"v":4,"type":"question","id":"c1","request":"q4","questions":[
            {"question":"Procedo?","header":"","multiSelect":false,"freeform":false,"options":[{"label":"Sì"},{"label":"No"}]}]}
            """#
        guard case let .question(_, question) = try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) else {
            Issue.record("Not a question")
            return
        }
        #expect(question.items.first?.allowsText == false)
        #expect(!question.isAnswered(by: [.init(text: "Forse")]))
        #expect(question.isAnswered(by: [.init(options: [1])]))
    }
}
