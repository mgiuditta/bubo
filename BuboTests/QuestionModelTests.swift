import Foundation
import Testing
@testable import Bubo

@Suite(.timeLimit(.minutes(1)))
struct QuestionModelTests {
    /// A keychain that counts how often the API key is read.
    final class Keychain {
        var reads = 0
        let key: String?

        init(key: String?) {
            self.key = key
        }
    }

    /// A bridge played by `/bin/sh` that answers only when `claude` gets the API key, and stops at the 5-hour limit otherwise.
    static let bridge = #"""
        while read line; do
          id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
          if [ -n "$ANTHROPIC_API_KEY" ]; then
            echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"a consumo\"}"
            echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
          else
            echo "{\"v\":4,\"type\":\"limit\",\"id\":\"$id\",\"window\":\"five_hour\",\"resetsAt\":1790852400}"
          fi
        done
        """#

    static let limit = Quota.Limit(window: "five_hour", resetsAt: Date(timeIntervalSince1970: 1_790_852_400))

    static func model(_ keychain: Keychain) -> QuestionModel {
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        return QuestionModel(cli: cli, orb: OrbControls(), bridgeExecutable: URL(filePath: "/bin/sh"),
                             bridgeArguments: ["-c", bridge]) {
            keychain.reads += 1
            return keychain.key
        }
    }

    static func ask(_ model: QuestionModel) async {
        model.prompt = "Ciao"
        model.ask()
        await model.answering?.value
    }

    // ADR 0003: at the limit Bubo proposes, and never moves to the API key on its own.
    @Test func aLimitNeverMovesToTheAPIKeyOnItsOwn() async {
        let keychain = Keychain(key: "sk-ant-test")
        let model = Self.model(keychain)

        await Self.ask(model)
        #expect(model.failure == .bridge(.limitReached(Self.limit)))
        model.retry()
        await model.answering?.value
        model.retry(model: Self.limit.otherModel)
        await model.answering?.value

        #expect(model.failure == .bridge(.limitReached(Self.limit)))
        #expect(model.answer.isEmpty)
        #expect(!model.usesAPIKey)
        #expect(keychain.reads == 0)
    }

    @Test func theAPIKeyAnswersOnlyAfterConsent() async {
        let keychain = Keychain(key: "sk-ant-test")
        let model = Self.model(keychain)
        await Self.ask(model)

        await model.useAPIKey()
        await model.answering?.value

        #expect(model.usesAPIKey)
        #expect(model.failure == nil)
        #expect(model.answer == "a consumo")
    }

    @Test func anAnsweredDomandaBecomesASessioneWithItsConversation() async {
        let model = Self.model(Keychain(key: "sk-ant-test"))
        await Self.ask(model)
        await model.useAPIKey()
        await model.answering?.value
        model.prompt = "Fallo"

        let draft = model.turnIntoSession()

        #expect(draft == SessionDraft(prompt: "Fallo", question: "Ciao", answer: "a consumo"))
        #expect(draft.firstPrompt("Fallo").contains("Ciao"))
        #expect(draft.firstPrompt("Fallo").contains("a consumo"))
        #expect(draft.firstPrompt("Fallo").hasSuffix("Fallo"))
    }

    @Test func aDomandaWithNoAnswerBecomesASessioneWithItsPrompt() async {
        let model = Self.model(Keychain(key: nil))
        await Self.ask(model)

        let draft = model.turnIntoSession()

        #expect(draft == SessionDraft(prompt: "Ciao"))
        #expect(draft.firstPrompt("Ciao") == "Ciao")
    }

    @Test func consentWithoutASavedKeyStaysOnTheSubscription() async {
        let model = Self.model(Keychain(key: nil))
        await Self.ask(model)

        await model.useAPIKey()

        #expect(model.failure == .apiKeyMissing)
        #expect(!model.usesAPIKey)
    }

    @Test func stoppingTheWaitForTheResetKeepsTheLimit() async {
        let model = Self.model(Keychain(key: nil))
        await Self.ask(model)

        model.resumeAfterReset()
        #expect(model.resumesAt == Self.limit.resetsAt)
        model.stop()

        #expect(model.resumesAt == nil)
        #expect(model.failure == .bridge(.limitReached(Self.limit)))
    }
}
