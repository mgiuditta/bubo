import Foundation
import Testing
@testable import Bubo

/// The interview that sets up the Secondo cervello (#656): rounds, then the map, then the Profilo and the Regole,
/// written only after the user's yes.
@Suite(.timeLimit(.minutes(1)))
struct SecondBrainInterviewTests {
    let folder: NotesFolder

    init() throws {
        folder = try NotesFolder()
    }

    /// A model that answers every turn with `answer`, played by `/bin/sh` reading it from a file.
    func model(answering answer: String) throws -> QuestionModel {
        let line = try JSONSerialization.data(withJSONObject: ["v": 4, "type": "text", "id": "@ID@", "text": answer])
        let file = folder.claude.folder.appending(path: "answer.jsonl")
        try (String(decoding: line, as: UTF8.self) + "\n{\"v\":4,\"type\":\"done\",\"id\":\"@ID@\"}\n")
            .write(to: file, atomically: true, encoding: .utf8)
        let bridge = """
            while read line; do
              id=$(echo "$line" | sed 's/.*"id":"\\([^"]*\\)".*/\\1/')
              sed "s/@ID@/$id/" '\(file.path)'
            done
            """
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        return QuestionModel(cli: cli, orb: OrbControls(), bridgeExecutable: URL(filePath: "/bin/sh"),
                             bridgeArguments: ["-c", bridge], apiKey: { nil }, onDevice: .off)
    }

    @Test func profileAndRulesAreWrittenOnlyAfterTheYes() async throws {
        let answer = """
            Ecco la mappa: Progetti/ per i progetti, Persone/ per le persone. Va bene?
            ```secondo-cervello
            {"azione": "usa", "cartella": "/altrove", "escluse": [], "profilo": "# Profilo\\nSviluppatore a Roma.",
             "regole": "# Regole\\nLe riunioni vanno in Bubo/Riunioni."}
            ```
            """
        let questions = try model(answering: answer)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let conversation = SecondBrainConversation(questions: questions,
                                                   secondBrain: SecondBrain(index: nil, defaults: defaults))
        let profile = folder.notes.appending(path: NoteWriter.profilePath)
        let rules = folder.notes.appending(path: NoteWriter.rulesPath)

        conversation.start(with: folder.notes, isNew: false)
        await questions.answering?.value
        conversation.receive()

        let proposal = try #require(conversation.proposal)
        #expect(proposal.profile == "# Profilo\nSviluppatore a Roma.")
        #expect(!FileManager.default.fileExists(atPath: folder.notes.appending(path: "Bubo").path))

        try conversation.apply()

        #expect(try String(contentsOf: profile, encoding: .utf8) == "# Profilo\nSviluppatore a Roma.\n")
        #expect(try String(contentsOf: rules, encoding: .utf8) == "# Regole\nLe riunioni vanno in Bubo/Riunioni.\n")
        #expect(conversation.proposal == nil)
    }

    @Test func intervistaReplacesTheDefaultMethod() throws {
        #expect(SecondBrainConversation.method(in: folder.notes) == SecondBrainConversation.defaultMethod)

        try folder.write("Fammi solo tre domande, una alla volta.\n", to: NoteWriter.interviewPath)
        let method = SecondBrainConversation.method(in: folder.notes)
        let instructions = SecondBrainConversation.instructions(folder: SecondBrainLocation(folder: folder.notes),
                                                                isConfigured: false, isNew: false, method: method)

        #expect(method == "Fammi solo tre domande, una alla volta.")
        #expect(instructions.contains(method))
        #expect(!instructions.contains(SecondBrainConversation.defaultMethod))
        #expect(instructions.contains("```secondo-cervello"))
    }

    @Test func anEmptyIntervistaKeepsTheDefaultMethod() throws {
        try folder.write("  \n", to: NoteWriter.interviewPath)

        #expect(SecondBrainConversation.method(in: folder.notes) == SecondBrainConversation.defaultMethod)
    }

    @Test func theCurrentProfileIsGivenToTheModel() throws {
        try folder.write("Lavoro in banca.", to: NoteWriter.profilePath)

        let instructions = SecondBrainConversation.instructions(folder: SecondBrainLocation(folder: folder.notes),
                                                                isConfigured: false, isNew: false)

        #expect(instructions.contains("Lavoro in banca."))
    }

    @Test func anEmptyProfileLeavesItsFileAsItIs() throws {
        try folder.write("Mio.", to: NoteWriter.profilePath)

        try NoteWriter(root: folder.notes).writeSetup(profile: "", rules: "Regola.")

        #expect(try String(contentsOf: folder.notes.appending(path: NoteWriter.profilePath), encoding: .utf8) == "Mio.")
        #expect(try String(contentsOf: folder.notes.appending(path: NoteWriter.rulesPath), encoding: .utf8) == "Regola.\n")
    }
}
