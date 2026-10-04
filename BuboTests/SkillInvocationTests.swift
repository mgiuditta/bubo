import Foundation
import Testing
@testable import Bubo

/// A skill `name` in a temporary folder, with `body` in its `SKILL.md`.
private func makeSkill(_ name: String, body: String = "Fai domande.") throws -> Skill {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: "\(UUID().uuidString)/\(name)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: "SKILL.md")
    try "---\ndescription: Prova\n---\n\(body)\n".write(to: file, atomically: true, encoding: .utf8)
    return try #require(Skill(file: file, name: name, directory: folder, source: .user))
}

/// `/name` at the start of a prompt, expanded for the models that do not run skills (#689).
struct SkillInvocationTests {
    @Test func aKnownSkillIsParsed() throws {
        let grill = try makeSkill("grill")

        let invocation = try #require(SkillInvocation(parsing: "  /grill   il mio piano ", among: [grill]))

        #expect(invocation.skill == grill)
        #expect(invocation.request == "il mio piano")
    }

    @Test func anUnknownSkillIsPlainText() throws {
        #expect(SkillInvocation(parsing: "/sconosciuta ciao", among: [try makeSkill("grill")]) == nil)
        #expect(SkillInvocation(parsing: "/", among: [try makeSkill("grill")]) == nil)
    }

    @Test func aSlashInsideTheSentenceCallsNothing() throws {
        #expect(SkillInvocation(parsing: "usa /grill sul piano", among: [try makeSkill("grill")]) == nil)
    }

    @Test func aPluginSkillIsCalledWithItsPrefix() throws {
        let wizard = try makeSkill("mp:wizard")

        let invocation = try #require(SkillInvocation(parsing: "/mp:wizard", among: [wizard]))

        #expect(invocation.skill.name == "mp:wizard")
        #expect(invocation.request.isEmpty)
    }

    @Test func onlyClaudeIsToldTheFolder() throws {
        let grill = try makeSkill("grill")
        let invocation = SkillInvocation(skill: grill, request: "il piano")
        let folder = try #require(grill.directory).path(percentEncoded: false)

        #expect(invocation.expanded() == "<skill name=\"grill\">\nFai domande.\n</skill>\n\nil piano")
        #expect(invocation.expanded(showingFolder: true).contains(folder))
        #expect(!invocation.expanded().contains(folder))
    }
}

/// The skill of a Domanda: it holds for its seguiti, and Nuova Domanda drops it.
@Suite(.timeLimit(.minutes(1)))
struct QuestionModelSkillTests {
    /// A bridge played by `/bin/sh` that says whether the prompt it got carries the skill, and the skill's folder.
    static let bridge = #"""
        while read -r line; do
          id=$(printf "%s" "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
          case "$line" in
            *'"dirs":['*'<skill name='*|*'<skill name='*'"dirs":['*) text="skill e cartella" ;;
            *'<skill name='*) text="skill" ;;
            *) text="senza skill" ;;
          esac
          echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"$text\"}"
          echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
        done
        """#

    let grill: Skill
    let model: QuestionModel

    init() throws {
        let grill = try makeSkill("grill")
        self.grill = grill
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        model = QuestionModel(cli: cli, orb: OrbControls(), bridgeExecutable: URL(filePath: "/bin/sh"),
                              bridgeArguments: ["-c", Self.bridge],
                              defaults: UserDefaults(suiteName: UUID().uuidString)!, onDevice: .off,
                              skills: { _ in [grill] })
    }

    func ask(_ text: String) async {
        model.prompt = text
        model.ask()
        await model.answering?.value
    }

    @Test func theSkillHoldsForTheSeguiti() async {
        await ask("/grill il mio piano")

        #expect(model.lastPrompt == "/grill il mio piano")
        #expect(model.activeSkill == grill)
        #expect(model.answer == "skill e cartella")

        await ask("E il secondo punto?")

        #expect(model.activeSkill == grill)
        #expect(model.answer == "skill e cartella")
    }

    @Test func aNewDomandaDropsTheSkill() async {
        await ask("/grill il mio piano")

        model.startNewQuestion()
        #expect(model.activeSkill == nil)
        await ask("Chi era Volta?")

        #expect(model.answer == "senza skill")
    }

    @Test func anUnknownSkillGoesAsItIs() async {
        await ask("/boh ciao")

        #expect(model.activeSkill == nil)
        #expect(model.answer == "senza skill")
    }

    @Test func claudeMayReadTheSkillFolder() throws {
        let folder = try #require(grill.directory)

        #expect(QuestionModel.readableDirectories(for: [], skill: grill) == [folder])
        #expect(QuestionModel.readableDirectories(for: []).isEmpty)
    }
}

/// A Sessione's `/name`: native for Claude, written into the prompt otherwise.
struct SessionSkillTests {
    @Test func claudeRunsASlashPromptOnItsOwn() throws {
        let grill = try makeSkill("grill")

        let (prompt, skill) = SessionStore.expandingSkill(in: "/grill il piano", among: [grill], forClaude: true)

        #expect(prompt == "/grill il piano")
        #expect(skill == nil)
    }

    @Test func copilotGetsTheSkillWritten() throws {
        let grill = try makeSkill("grill")

        let (prompt, skill) = SessionStore.expandingSkill(in: "/grill il piano", among: [grill], forClaude: false)

        #expect(prompt == SkillInvocation(skill: grill, request: "il piano").expanded())
        #expect(skill == grill)
    }

    @Test func aDomandaBeforeTheRequestDoesNotHideTheSkill() throws {
        let grill = try makeSkill("grill")
        let draft = SessionDraft(turns: [QuestionTurn(prompt: "Chi era Volta?", answer: "Un fisico.")])
        let first = draft.firstPrompt("/grill il piano")
        #expect(SessionStore.mayCallSkill(first))

        let (prompt, skill) = SessionStore.expandingSkill(in: first, among: [grill], forClaude: true)

        #expect(skill == grill)
        #expect(prompt.hasPrefix("<skill name=\"grill\">"))
        #expect(prompt.hasSuffix(QuestionTurn.asking("il piano")))
    }
}
