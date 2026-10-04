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
                             bridgeArguments: ["-c", bridge], apiKey: {
                                 keychain.reads += 1
                                 return keychain.key
                             }, onDevice: .off)
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

        #expect(draft == SessionDraft(prompt: "Fallo", turns: [QuestionTurn(prompt: "Ciao", answer: "a consumo")]))
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

    /// A classifier engine that always answers `type`, so the route does not depend on the rules' words.
    nonisolated struct FixedEngine: ClassificationEngine {
        let type: RequestType
        var budget: Duration { .seconds(1) }

        func classification(of input: ClassifierInput) async throws -> RequestClassification {
            RequestClassification(type: type, categoria: .chat, variante: nil, engine: .foundationModels)
        }
    }

    /// A bridge played by `/bin/sh` that answers only the router's choice for Scrittura and Fatto breve: for Sonnet
    /// medio the SDK downgrades the effort to basso; Haiku has no effort. Anything else is an error.
    static let routedBridge = #"""
        while read line; do
          id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
          case "$line" in
            *'"effort":"medium"'*'"model":"sonnet"'*)
              by='"model":"claude-sonnet-5-5","effort":"low"' ;;
            *'"effort"'*) by='' ;;
            *'"model":"haiku"'*)
              by='"model":"claude-haiku-4-5-20251001"' ;;
            *) by='' ;;
          esac
          if [ -z "$by" ]; then
            echo "{\"v\":4,\"type\":\"error\",\"id\":\"$id\",\"message\":\"rotta sbagliata\"}"
            continue
          fi
          echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"Ecco\"}"
          echo "{\"v\":4,\"type\":\"usage\",\"id\":\"$id\",\"mode\":\"subscription\",\"cost\":0.012,\"basis\":\"list\",\"complete\":true,\"models\":[]}"
          echo "{\"v\":4,\"type\":\"answeredBy\",\"id\":\"$id\",$by}"
          echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
        done
        """#

    /// - Parameters:
    ///   - onDevice: Apple's model as the router measures with; off, so Fatto breve and Riassunto go to Haiku.
    ///   - answerer: What answers on the Mac; one that fails when `nil`, so no test reaches the real model.
    static func routedModel(_ type: RequestType, onDevice: OnDeviceModel = .off,
                            answerer: (any OnDeviceAnswering)? = nil) throws -> QuestionModel {
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        let orb = OrbControls()
        let rules = RuleClassifier(catalogo: try Catalogo(bundle: .main))
        let intake = IntakePipeline(orb: orb, onDevice: onDevice) {
            RequestClassifier(engines: [FixedEngine(type: type)], rules: rules)
        }
        return QuestionModel(cli: cli, orb: orb, intake: intake, bridgeExecutable: URL(filePath: "/bin/sh"),
                             bridgeArguments: ["-c", routedBridge], defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             onDeviceAnswerer: answerer ?? FakeAnswerer(chunks: [], failure: .assetsUnavailable))
    }

    /// Answers on the Mac with `chunks`, then fails with `failure` if one is given.
    nonisolated struct FakeAnswerer: OnDeviceAnswering {
        enum Failure: Error { case assetsUnavailable }

        let chunks: [String]
        var failure: Failure?

        func answer(to question: String, attachments: [Allegato]) -> AsyncThrowingStream<String, any Error> {
            AsyncThrowingStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish(throwing: failure)
            }
        }
    }

    // A Domanda the router keeps on the Mac never starts the bridge: `/bin/false` would fail it.
    @Test func aRouteOnTheMacAnswersWithoutTheBridge() async throws {
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        let orb = OrbControls()
        let rules = RuleClassifier(catalogo: try Catalogo(bundle: .main))
        let intake = IntakePipeline(orb: orb, onDevice: .fitting) {
            RequestClassifier(engines: [FixedEngine(type: .shortFact)], rules: rules)
        }
        let model = QuestionModel(cli: cli, orb: orb, intake: intake, bridgeExecutable: URL(filePath: "/bin/false"),
                                  defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                  onDeviceAnswerer: FakeAnswerer(chunks: ["Li", "ma."]))
        await Self.ask(model)

        #expect(model.failure == nil)
        #expect(model.answer == "Lima.")
        let line = try #require(model.routedAnswer)
        #expect(line.route == .onDevice(.shortFact, runnerUp: nil))
        #expect(line.provider == nil)
        #expect(line.cost == .free)
        // Above Apple FM, "Rifai più forte" starts the Scala.
        #expect(model.strongerRoute == .stronger(Scala.Step(family: .haiku, effort: nil)))
    }

    @Test func appleFMFailingBeforeTheFirstTokenFallsBackToHaiku() async throws {
        let model = try Self.routedModel(.shortFact, onDevice: .fitting,
                                         answerer: FakeAnswerer(chunks: [], failure: .assetsUnavailable))
        await Self.ask(model)

        #expect(model.failure == nil)
        #expect(model.answer == "Ecco")
        let line = try #require(model.routedAnswer)
        #expect(line.route == Route(family: .haiku, model: "haiku", effort: nil, reason: .type(.shortFact, runnerUp: nil),
                                    onDeviceFallback: .failed))
        #expect(line.provider == .anthropic)
    }

    @Test func appleFMFailingAfterTheFirstTokenStaysAFailure() async throws {
        let model = try Self.routedModel(.shortFact, onDevice: .fitting,
                                         answerer: FakeAnswerer(chunks: ["Li"], failure: .assetsUnavailable))
        await Self.ask(model)

        #expect(model.failure == .unexpected)
        #expect(model.answer == "Li")
        #expect(model.routedAnswer?.route.destination == .onDevice)
    }

    // The reason line under the answer shows the effort the SDK applied, not the one the router asked for.
    @Test func theLineShowsTheEffortTheSDKDowngradedTo() async throws {
        let model = try Self.routedModel(.writing)
        await Self.ask(model)

        #expect(model.failure == nil)
        #expect(model.answer == "Ecco")
        let line = try #require(model.routedAnswer)
        #expect(line.route == Route(family: .sonnet, model: "sonnet", effort: .medium, reason: .type(.writing, runnerUp: nil)))
        #expect(line.answeringModel == AnsweringModel(model: "claude-sonnet-5-5", effort: .low))
        #expect(line.cost == .listValue(Decimal(string: "0.012")!))
    }

    @Test func haikuGoesWithoutEffortAndAnswersWithout() async throws {
        let model = try Self.routedModel(.shortFact)
        await Self.ask(model)

        #expect(model.failure == nil)
        let line = try #require(model.routedAnswer)
        #expect(line.route.effort == nil)
        #expect(line.answeringModel == AnsweringModel(model: "claude-haiku-4-5-20251001", effort: nil))
        #expect(line.answeringModel?.name == "Haiku 4.5")
    }

    @Test func aModelPickedByTheUserIsSaidSo() async throws {
        let model = try Self.routedModel(.writing)
        await Self.ask(model)
        model.retry(model: "haiku")
        await model.answering?.value

        #expect(model.routedAnswer?.route == .chosen("haiku"))
        #expect(model.routedAnswer?.answeringModel?.name == "Haiku 4.5")
    }

    /// A bridge played by `/bin/sh` that always answers with Sonnet at medium effort.
    static let sonnetBridge = #"""
        while read line; do
          id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
          echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"risposta\"}"
          echo "{\"v\":4,\"type\":\"answeredBy\",\"id\":\"$id\",\"model\":\"claude-sonnet-5-5\",\"effort\":\"medium\"}"
          echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
        done
        """#

    // "Rifai più forte" climbs one step for that turn only: the next Domanda takes the router's default again.
    @Test func rifaiPiuForteLeavesTheDefaultAlone() async {
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        let orb = OrbControls()
        let model = QuestionModel(cli: cli, orb: orb, intake: IntakePipeline(orb: orb, makeClassifier: { nil }),
                                  bridgeExecutable: URL(filePath: "/bin/sh"), bridgeArguments: ["-c", Self.sonnetBridge],
                                  apiKey: { nil })
        await Self.ask(model)
        #expect(model.strongerRoute == .stronger(Scala.Step(family: .sonnet, effort: .high)))

        model.retryStronger()
        await model.answering?.value
        #expect(model.routedAnswer?.route == .stronger(Scala.Step(family: .sonnet, effort: .high)))

        await Self.ask(model)
        #expect(model.routedAnswer?.route.reason == .unclassified)
    }
}

/// #678: a Claude Domanda runs in the Secondo cervello when there is one, reading it but not its excluded folders.
struct QuestionWorkplaceTests {
    @Test func aReachableSecondBrainIsTheWorkplace() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Cervello-\(UUID().uuidString)",
                                                                      directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var location = SecondBrainLocation(folder: folder)
        location.excludedFolders = ["Privato"]

        let workplace = try QuestionModel.workplace(in: location)

        #expect(workplace.directory == location.url)
        let hidden = location.url.appending(path: "Privato", directoryHint: .isDirectory)
        #expect(workplace.readOnly == ReadOnlyTurn(isInSecondBrain: true, hiddenDirectories: [hidden]))
    }

    @Test(arguments: [false, true])
    func withoutAReachableSecondBrainTheDomandeFolderIsTheWorkplace(isConfigured: Bool) throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "Sparito-\(UUID().uuidString)")
        let location = isConfigured ? SecondBrainLocation(folder: missing) : nil

        let workplace = try QuestionModel.workplace(in: location)

        #expect(workplace.directory == (try QuestionModel.directory()))
        #expect(workplace.readOnly == ReadOnlyTurn())
    }
}
