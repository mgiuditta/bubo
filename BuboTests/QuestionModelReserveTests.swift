import Foundation
import Testing
@testable import Bubo

/// The Riserva in the Domande (#726, ADR 0014): only Quota or a limit of the Motore principale moves a Domanda to the
/// other Motore, and the next one tries the principale again.
@Suite(.timeLimit(.minutes(1)))
struct QuestionModelReserveTests {
    let defaults = UserDefaults(suiteName: "QuestionModelReserveTests-\(UUID().uuidString)")!

    /// A bridge played by `/bin/sh`: Claude stops at its limit on a prompt with «@claude-finita», Copilot on one with
    /// «@copilot-finita»; both fail as the network does on «@rete-giu», and otherwise answer with their name.
    static let bridge = #"""
        while read line; do
          id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
          case "$line" in
            *'"type":"copilotQuestion"'*)
              case "$line" in
                *@copilot-finita*) echo "{\"v\":4,\"type\":\"copilotLimit\",\"id\":\"$id\",\"message\":\"Crediti finiti\"}" ;;
                *@rete-giu*) echo "{\"v\":4,\"type\":\"error\",\"id\":\"$id\",\"message\":\"fetch failed\"}" ;;
                *) echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"da copilot\"}"
                   echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
              esac ;;
            *'"type":"ask"'*)
              case "$line" in
                *@claude-finita*) echo "{\"v\":4,\"type\":\"limit\",\"id\":\"$id\",\"window\":\"five_hour\",\"resetsAt\":1790852400}" ;;
                *@rete-giu*) echo "{\"v\":4,\"type\":\"error\",\"id\":\"$id\",\"message\":\"Connection error.\"}" ;;
                *) echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"da claude\"}"
                   echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}" ;;
              esac ;;
          esac
        done
        """#

    /// A Domanda model whose Motore principale is `primary`, with the Riserva when `hasReserve`, both Motori installed.
    func model(primary: Session.Engine, hasReserve: Bool) throws -> QuestionModel {
        defaults.set(primary.rawValue, forKey: PrimaryEngine.engineKey)
        defaults.set(hasReserve, forKey: PrimaryEngine.reserveKey)
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        let rules = try RuleClassifier(catalogo: Catalogo(bundle: .main))
        let orb = OrbControls()
        let intake = IntakePipeline(orb: orb, onDevice: .off) {
            RequestClassifier(engines: [QuestionModelTests.FixedEngine(type: .writing)], rules: rules)
        }
        let endpoints = EndpointSettings(defaults: defaults)
        endpoints.grantCopilotConsent()
        return QuestionModel(cli: cli, orb: orb, intake: intake, bridgeExecutable: URL(filePath: "/bin/sh"),
                             bridgeArguments: ["-c", Self.bridge], defaults: defaults, apiKey: { nil },
                             endpoints: endpoints,
                             preferences: TypePreferences(defaults: defaults),
                             copilot: { URL(filePath: "/opt/homebrew/bin/copilot") })
    }

    func ask(_ prompt: String, of model: QuestionModel) async {
        model.startNewQuestion()
        model.prompt = prompt
        model.ask()
        await model.answering?.value
    }

    func reason(of model: QuestionModel) throws -> String {
        String(localized: RouterLine.reason(for: try #require(model.routedAnswer?.route)))
    }

    @Test func claudeAtItsLimitHandsTheDomandaToCopilot() async throws {
        let model = try model(primary: .claude, hasReserve: true)

        await ask("Ciao @claude-finita", of: model)

        #expect(model.failure == nil)
        #expect(model.answer == "da copilot")
        #expect(model.routedAnswer?.route.exhaustedEngine == .claude)
        #expect(try reason(of: model) == String(localized: "Quota di Claude finita: risponde Copilot"))
    }

    @Test func copilotAtItsLimitHandsTheDomandaToClaude() async throws {
        let model = try model(primary: .copilot, hasReserve: true)

        await ask("Ciao @copilot-finita", of: model)

        #expect(model.failure == nil)
        #expect(model.answer == "da claude")
        #expect(model.routedAnswer?.provider == .anthropic)
        #expect(try reason(of: model) == String(localized: "Quota di Copilot finita: risponde Claude"))
    }

    @Test func afterTheRiservaTheNextDomandaTriesThePrincipaleAgain() async throws {
        let model = try model(primary: .claude, hasReserve: true)
        await ask("Ciao @claude-finita", of: model)

        await ask("Ciao", of: model)

        #expect(model.answer == "da claude")
        #expect(model.routedAnswer?.route.exhaustedEngine == nil)
    }

    @Test func withoutTheRiservaTheLimitStaysTodaysFailure() async throws {
        let claude = try model(primary: .claude, hasReserve: false)
        await ask("Ciao @claude-finita", of: claude)
        #expect(claude.failure == .bridge(.limitReached(QuestionModelTests.limit)))
        #expect(claude.answer.isEmpty)

        let copilot = try model(primary: .copilot, hasReserve: false)
        await ask("Ciao @copilot-finita", of: copilot)
        #expect(copilot.failure == .copilotFailed("Crediti finiti"))
        #expect(copilot.answer.isEmpty)
    }

    @Test(arguments: [Session.Engine.claude, .copilot])
    func aNetworkErrorNeverChangesMotore(primary: Session.Engine) async throws {
        let model = try model(primary: primary, hasReserve: true)

        await ask("Ciao @rete-giu", of: model)

        #expect(model.answer.isEmpty)
        #expect(model.routedAnswer?.route.exhaustedEngine == nil)
        #expect(model.failure == (primary == .claude ? .bridge(.failed(message: "Connection error."))
                                                     : .copilotFailed("fetch failed")))
    }
}
