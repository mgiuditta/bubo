import Foundation
import os

/// A Domanda typed in the HUD, answered by `claude` through the agent bridge, or by Apple Foundation Models on the Mac.
@Observable
final class QuestionModel {
    /// What the user is typing.
    var prompt = ""
    /// The answer so far, growing as it streams.
    private(set) var answer = ""
    /// Whether an answer is on its way.
    private(set) var isAnswering = false
    /// Why the last Domanda got no answer, if it failed.
    private(set) var failure: QuestionFailure?
    /// The Quota last reported by `claude` through the bridge this model owns, or else the one saved at the last
    /// launch; empty when there is neither.
    private(set) var quota: Quota
    /// When the last prompt will be asked again, while waiting for a limit's reset.
    private(set) var resumesAt: Date?
    /// Whether `claude` runs with the API key, paid per use; only after the user's consent (ADR 0003).
    private(set) var usesAPIKey = false
    /// What the reason line under the last answer says: who answered, why, and at what cost; `nil` before the first.
    private(set) var routedAnswer: RoutedAnswer?
    /// The note the last Domanda saved in the Secondo cervello ("Ricordati questo"), if any.
    private(set) var savedNote: URL?
    /// The Sintesi parlata while Bubo says it, as subtitles; `nil` when Bubo is silent.
    private(set) var subtitle: String?
    /// Whether to invite the user to download a better voice: Bubo spoke with a basic-quality one, and the user did not
    /// close the invitation yet.
    private(set) var invitesBetterVoice = false
    /// The endpoints the user left out of "Rifai con…" for this Domanda, by not giving their consent.
    private(set) var declinedEndpoints: Set<String> = []
    /// The road every Domanda takes to `claude`, moving the Orb on the way.
    let intake: IntakePipeline
    /// The OpenAI-compatible endpoints "Rifai con…" offers, and the clouds allowed to receive Domande.
    let endpoints: EndpointSettings

    /// Creates a model that finds `claude` with `cli`, answers its `cerca` tool with `index` and its `ricorda` tool
    /// with `secondBrain`.
    ///
    /// - Parameters:
    ///   - orb: The Orb that thinks, morphs and works with each Domanda, and plays the Orbite when the prompt asks for it.
    ///   - intake: The pipeline the Domande go through; one driving `orb` when `nil`.
    ///   - bridgeExecutable: The agent bridge; tests pass a stand-in.
    ///   - bridgeArguments: The arguments of `bridgeExecutable`.
    ///   - defaults: Where the last Quota is kept between launches.
    ///   - apiKey: Reads the saved API key, from `APIKeyStore` when `nil`; called only after the user chose it.
    ///   - endpoints: The OpenAI-compatible endpoints and their consents.
    ///   - endpointClient: The client that asks them; tests pass one served by a stand-in server.
    ///   - endpointKey: Reads an endpoint's key, from `APIKeyStore` when `nil`; called only when that endpoint answers.
    ///   - speaker: Says the Sintesi parlata of the Domande asked by voice; the voices of the Mac when `nil`.
    ///   - onDevice: Apple's model on the Mac, which `intake` measures with when it is `nil`.
    ///   - onDeviceAnswerer: Answers the Domande the router keeps on the Mac; Foundation Models on `onDevice` when `nil`.
    init(cli: ClaudeCLI = ClaudeCLI(), index: SearchIndex? = nil, secondBrain: SecondBrain? = nil,
         orb: OrbControls = .shared, intake: IntakePipeline? = nil,
         bridgeExecutable: URL = Bundle.main.bundleURL.appending(path: "Contents/Helpers/bubo-agent"),
         bridgeArguments: [String] = [], defaults: UserDefaults = .standard,
         apiKey: (() async throws -> String?)? = nil, endpoints: EndpointSettings = .shared,
         endpointClient: OpenAICompatibleClient = OpenAICompatibleClient(),
         endpointKey: ((OpenAICompatibleEndpoint) async throws -> String?)? = nil,
         speaker: (any VoiceSpeaker)? = nil,
         onDevice: OnDeviceModel = OnDeviceModel(), onDeviceAnswerer: (any OnDeviceAnswering)? = nil) {
        quota = Quota.saved(in: defaults)
        self.defaults = defaults
        self.cli = cli
        self.index = index
        self.secondBrain = secondBrain
        self.orb = orb
        self.intake = intake ?? IntakePipeline(orb: orb, onDevice: onDevice)
        self.onDeviceAnswerer = onDeviceAnswerer ?? FoundationModelsAnswerer(model: onDevice)
        self.bridgeExecutable = bridgeExecutable
        self.bridgeArguments = bridgeArguments
        let store = APIKeyStore()
        self.apiKey = apiKey ?? { try await store.key() }
        self.endpoints = endpoints
        self.endpointClient = endpointClient
        self.endpointKey = endpointKey ?? { try await APIKeyStore(account: $0.keychainAccount).key() }
        self.makeSpeaker = speaker.map { speaker in { speaker } } ?? { SpeechOutput() }
    }

    /// The task answering the last Domanda, or waiting to ask it again.
    @ObservationIgnored private(set) var answering: Task<Void, Never>?
    @ObservationIgnored private let cli: ClaudeCLI
    @ObservationIgnored private let index: SearchIndex?
    @ObservationIgnored private let secondBrain: SecondBrain?
    @ObservationIgnored private let orb: OrbControls
    @ObservationIgnored private let bridgeExecutable: URL
    @ObservationIgnored private let bridgeArguments: [String]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let apiKey: () async throws -> String?
    @ObservationIgnored private let endpointClient: OpenAICompatibleClient
    @ObservationIgnored private let endpointKey: (OpenAICompatibleEndpoint) async throws -> String?
    @ObservationIgnored private let makeSpeaker: () -> any VoiceSpeaker
    /// The voice, made at the first Domanda asked by voice.
    @ObservationIgnored private lazy var speaker = makeSpeaker()
    /// The Sintesi parlata being said.
    @ObservationIgnored private(set) var speaking: Task<Void, Never>?
    @ObservationIgnored private let onDeviceAnswerer: any OnDeviceAnswering
    /// How long the first token took, the last time each choice of "Rifai con…" answered.
    @ObservationIgnored private var firstTokens: [String: Duration] = [:]
    @ObservationIgnored private var bridge: AgentBridge?
    @ObservationIgnored private var lastPrompt = ""
    /// Whether the Quota was asked for, or reported by `claude`, since launch.
    @ObservationIgnored private var hasFreshQuota = false
    /// How many times `claude` reported the Quota since launch, to tell whether a turn moved the 5-hour window.
    @ObservationIgnored private var quotaReports = 0
    /// The Claude models the account offers, read with the Quota; `nil` until then, and the router does without.
    @ObservationIgnored private var catalog: ModelCatalog?
    /// The strongest effort each family turned out to accept, when the SDK lowered the one asked for (an organization's
    /// `maxEffortLevel`): the Scala skips the steps above it from then on.
    @ObservationIgnored private var effortCaps: [ModelFamily: Effort] = [:]

    /// The step of the Scala above the last answer's, for "Rifai più forte"; `nil` while answering, before the first
    /// answer and at the top, where the command is off.
    ///
    /// Apple Foundation Models sits below the whole Scala: above it is the first step, Haiku.
    var strongerRoute: Route? {
        guard !isAnswering, !answer.isEmpty, let routedAnswer else { return nil }
        let scala = Scala(catalog: catalog, effortCaps: effortCaps)
        let step = routedAnswer.route.destination == .onDevice
            ? scala.steps.first
            : routedAnswer.route.step(answeredBy: routedAnswer.answeringModel).flatMap(scala.step(above:))
        return step.map(Route.stronger)
    }

    /// The choices of "Rifai con…" near the last answer, without the endpoints the user left out for this Domanda;
    /// empty while answering and before the first Domanda.
    var retryAlternatives: [RetryAlternative] {
        guard !isAnswering, !lastPrompt.isEmpty, let routedAnswer else { return [] }
        let current = routedAnswer.endpoint == nil ? routedAnswer.route.step(answeredBy: routedAnswer.answeringModel) : nil
        return RetryAlternative.alternatives(around: current, on: Scala(catalog: catalog, effortCaps: effortCaps),
                                             endpoints: endpoints.ready.filter { !declinedEndpoints.contains($0.id) },
                                             answeredBy: routedAnswer.endpoint?.id)
            .map { alternative in
                var alternative = alternative
                alternative.firstToken = firstTokens[alternative.id]
                return alternative
            }
    }

    /// The endpoints with a model that the user left out of "Rifai con…" for this Domanda.
    var excludedEndpoints: [OpenAICompatibleEndpoint] {
        endpoints.ready.filter { declinedEndpoints.contains($0.id) }
    }

    /// Whether picking `alternative` must first ask the user's consent: a cloud that is not Claude, never allowed.
    func needsConsent(for alternative: RetryAlternative) -> Bool {
        guard case let .endpoint(endpoint) = alternative.target else { return false }
        return !endpoint.isOnMac && !endpoints.consents.contains(endpoint.id)
    }

    /// Asks the last prompt again with `alternative`, for this turn only: the router's default does not change.
    ///
    /// A cloud that is not Claude without the user's consent receives nothing: the client refuses before sending.
    func retry(with alternative: RetryAlternative) {
        switch alternative.target {
        case let .claude(step): start(lastPrompt, route: .retried(step))
        case let .endpoint(endpoint): start(lastPrompt, endpoint: endpoint)
        }
    }

    /// Remembers that the user did not allow `endpoint`: it leaves "Rifai con…" until the next Domanda.
    func decline(_ endpoint: OpenAICompatibleEndpoint) {
        declinedEndpoints.insert(endpoint.id)
    }

    /// Asks the typed or dictated prompt, replacing any answer in progress; the Orbite's word plays it instead.
    func ask() {
        ask(speaksAnswer: false)
    }

    /// Asks the prompt said with push-to-talk, like `ask()`, and says the Sintesi parlata of the answer.
    func askByVoice() {
        ask(speaksAnswer: true)
    }

    /// Hides the invitation to download a better voice, for good.
    func dismissBetterVoice() {
        invitesBetterVoice = false
        defaults.set(true, forKey: Self.betterVoiceDismissedKey)
    }

    private static let betterVoiceDismissedKey = "voice.betterVoiceDismissed"

    private func ask(speaksAnswer: Bool) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        prompt = ""
        // No Domanda, no token: the Orb plays the Orbite and the last answer stays.
        if Orbite.isPlayed(by: text) {
            orb.playOrbite()
            return
        }
        lastPrompt = text
        declinedEndpoints = []
        start(text, speaksAnswer: speaksAnswer)
    }

    /// Asks the last prompt again.
    func retry() {
        start(lastPrompt)
    }

    /// Asks the last prompt again with `model`, a `claude` alias such as `sonnet`, instead of the router's choice.
    func retry(model: String) {
        start(lastPrompt, route: .chosen(model))
    }

    /// Asks the last prompt again one step up the Scala, for this turn only: the router's default does not change.
    func retryStronger() {
        guard let strongerRoute else { return }
        start(lastPrompt, route: strongerRoute)
    }

    /// Stops the answer in progress, keeping what arrived, or stops waiting for a reset.
    func stop() {
        answering?.cancel()
        stopSpeaking()
        resumesAt = nil
    }

    /// Stops the Sintesi parlata being said, if any, with the audio stopped before it returns: the Orb leaves Parla, and
    /// a Morph already started still runs to its end (spec 08).
    func stopSpeaking() {
        guard let speaking else { return }
        speaker.stop()
        speaking.cancel()
        self.speaking = nil
        subtitle = nil
    }

    /// Stops the Domanda and hands it to a new Sessione: what is typed, and the last prompt with what arrived of its
    /// answer; with no answer, what is typed or else the last prompt.
    func turnIntoSession() -> SessionDraft {
        stop()
        let typed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return SessionDraft(prompt: typed.isEmpty ? lastPrompt : typed) }
        return SessionDraft(prompt: typed, question: lastPrompt, answer: answer)
    }

    /// Waits until the limit that stopped the last Domanda resets, then asks it again.
    func resumeAfterReset() {
        guard case let .bridge(.limitReached(limit)) = failure, let resetsAt = limit.resetsAt else { return }
        answering?.cancel()
        resumesAt = resetsAt
        answering = Task {
            // A few seconds past the reset, so the window has surely started again; the wait runs on through sleep.
            try? await Task.sleep(for: .seconds(max(0, resetsAt.timeIntervalSinceNow) + 5))
            guard !Task.isCancelled else { return }
            resumesAt = nil
            start(lastPrompt)
        }
    }

    /// Moves the Domande and the Sessioni to the API key until Bubo quits, then asks the last prompt again.
    ///
    /// Called only when the user confirms (ADR 0003): Bubo never moves to the API key on its own.
    func useAPIKey() async {
        do {
            guard try await apiKey() != nil else {
                failure = .apiKeyMissing
                return
            }
        } catch {
            Logger.agent.error("API key not read: \(String(describing: error), privacy: .public)")
            failure = .unexpected
            return
        }
        moveToAPIKey()
        start(lastPrompt)
    }

    /// Moves the Domande and the Sessioni to the saved API key until Bubo quits, asking nothing again.
    ///
    /// Called only when the user chooses it (ADR 0003).
    func moveToAPIKey() {
        moveCredential(toAPIKey: true)
    }

    /// Moves the Domande and the Sessioni back to the login of `claude`, after a refused API key.
    func moveToSubscription() {
        moveCredential(toAPIKey: false)
    }

    private func moveCredential(toAPIKey: Bool) {
        usesAPIKey = toAPIKey
        // Conversations in progress end on the old bridge; the next one starts with the new credential.
        bridge?.closeWhenIdle()
        bridge = nil
    }

    /// Reads the Quota without a Domanda, unless it was read or reported since launch; with no answer the saved one
    /// stays.
    ///
    /// It starts a `claude`, so never at launch (spec 25): only when the user opens the HUD. After that the Domande and
    /// the Sessioni keep it fresh.
    func readQuotaIfNeeded() async {
        guard !hasFreshQuota else { return }
        hasFreshQuota = true
        do {
            try await readyBridge().readQuota()
        } catch {
            Logger.agent.notice("Quota not read: \(String(describing: error), privacy: .public)")
        }
    }

    /// - Parameters:
    ///   - route: The user's choice for this turn; `nil` for the router's.
    ///   - endpoint: The OpenAI-compatible endpoint that answers instead of `claude`, picked in "Rifai con…".
    ///   - speaksAnswer: Whether the Domanda was asked by voice, and Bubo says the Sintesi parlata of the answer.
    private func start(_ text: String, route: Route? = nil, endpoint: OpenAICompatibleEndpoint? = nil,
                       speaksAnswer: Bool = false) {
        answering?.cancel()
        stopSpeaking()
        answer = ""
        failure = nil
        resumesAt = nil
        savedNote = nil
        routedAnswer = nil
        isAnswering = true
        answering = Task {
            if let endpoint {
                await stream(text, from: endpoint)
            } else {
                await stream(text, route: route, speaksAnswer: speaksAnswer)
            }
        }
    }

    /// Streams `endpoint`'s answer: the Domanda's text only, straight from the Mac.
    private func stream(_ text: String, from endpoint: OpenAICompatibleEndpoint) async {
        defer { isAnswering = false }
        let submission = await intake.submit(Richiesta(text: text), to: endpoint.provider, catalog: catalog)
        defer { intake.finish(submission) }
        guard !Task.isCancelled else { return }
        var routedAnswer = RoutedAnswer(route: .retriedElsewhere, provider: endpoint.provider, endpoint: endpoint)
        routedAnswer.answeringModel = AnsweringModel(model: endpoint.model, effort: nil)
        self.routedAnswer = routedAnswer
        let start = ContinuousClock.now
        var waitingForFirstToken = true
        do {
            // The key is read only now that this endpoint answers, and goes only into its request.
            let key = try await endpointKey(endpoint)
            for try await event in endpointClient.answer(text, from: endpoint, consents: endpoints.consents, key: key) {
                switch event {
                case let .text(chunk):
                    if waitingForFirstToken {
                        waitingForFirstToken = false
                        firstTokens[RetryAlternative(target: .endpoint(endpoint)).id] = ContinuousClock.now - start
                        intake.beginWorking(on: submission)
                    }
                    answer += chunk
                case let .usage(input, output):
                    self.routedAnswer?.endpointTokens = input + output
                }
            }
        } catch is CancellationError {
        } catch let error as OpenAICompatibleError {
            Logger.agent.error("Endpoint \(endpoint.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            failure = .endpoint(error)
        } catch {
            Logger.agent.error("Endpoint key not read: \(String(describing: error), privacy: .public)")
            failure = .unexpected
        }
    }

    private func stream(_ text: String, route chosen: Route?, speaksAnswer: Bool) async {
        defer { isAnswering = false }
        let signpostID = Signposts.signposter.makeSignpostID()
        var waitingForFirstToken: OSSignpostIntervalState? =
            Signposts.signposter.beginInterval("Domanda, primo token", id: signpostID)
        defer { waitingForFirstToken.map { Signposts.signposter.endInterval("Domanda, primo token", $0) } }
        // Anthropic's Tinta while the router decides; a Domanda it keeps on the Mac takes the neutral one.
        let richiesta = Richiesta(text: text)
        let submission = await intake.submit(richiesta, to: .anthropic, catalog: catalog)
        defer { intake.finish(submission) }
        var route = chosen ?? submission.route
        // Asked by voice, the model writes the Sintesi parlata first, so that the voice starts with the answer.
        let asked = speaksAnswer ? text + SpokenSummary.instruction : text
        if route.destination == .onDevice {
            guard !Task.isCancelled else { return }
            routedAnswer = RoutedAnswer(route: route, provider: nil)
            do {
                var summary = speaksAnswer ? SpokenSummary() : nil
                var firstAudio: OSSignpostIntervalState?
                for try await chunk in onDeviceAnswerer.answer(to: asked, attachments: richiesta.attachments) {
                    if let state = waitingForFirstToken {
                        Signposts.signposter.endInterval("Domanda, primo token", state)
                        waitingForFirstToken = nil
                        intake.beginWorking(on: submission)
                        if speaksAnswer { firstAudio = Signposts.beginInterval(.voiceFirstAudio) }
                    }
                    answer += summary?.read(chunk) ?? chunk
                    if let line = summary?.line {
                        summary = nil
                        say(line, for: submission, firstAudio: firstAudio)
                    }
                }
                if var summary {
                    answer += summary.finish()
                    if let line = summary.line { say(line, for: submission, firstAudio: firstAudio) }
                }
                Logger.agent.info("Domanda answered on the Mac")
                return
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                // After the first token the answer is under way: a failure stays a failure.
                guard waitingForFirstToken != nil else {
                    Logger.agent.error("Apple FM failed mid-answer: \(String(describing: error), privacy: .public)")
                    failure = .unexpected
                    return
                }
                // Before it, once, Haiku answers instead and the reason line says why.
                Logger.agent.notice("Apple FM failed, Haiku answers: \(String(describing: error), privacy: .public)")
                route = Route(family: .haiku, model: ModelFamily.haiku.alias, effort: nil, reason: route.reason,
                              onDeviceFallback: .failed)
                intake.answer(submission, movedTo: .anthropic)
            }
        }
        let started = ContinuousClock.now
        let windowBefore = quotaReports > 0 ? quota.fiveHour : nil
        let reportsBefore = quotaReports
        // A Domanda replaced while it was classified leaves the line to the newer one.
        if !Task.isCancelled { routedAnswer = RoutedAnswer(route: route, provider: .anthropic) }
        defer {
            // Only a window `claude` reported both before and during the turn says what the turn used.
            if !Task.isCancelled, quotaReports > reportsBefore {
                routedAnswer?.fiveHourShare = RoutedAnswer.fiveHourShare(from: windowBefore, to: quota.fiveHour)
            }
        }
        do {
            let bridge = try await readyBridge()
            // The Varianti the agent may give the Orb at work: the ones near the Richiesta's Categoria first.
            let rosa = Catalogo.bundled?.rosa(around: submission.classification?.categoria) ?? []
            let stream = bridge.ask(asked, in: try Self.directory(), model: route.model, effort: route.effort,
                                    remembers: true, rosa: rosa,
                                    progress: { [orb] progress in
                                        if case let .variante(nome) = progress { orb.showWork(nome) }
                                    },
                                    usage: { [weak self] in self?.routedAnswer?.usage = $0 },
                                    answeredBy: { [weak self] in
                                        self?.routedAnswer?.answeringModel = $0
                                        self?.learnEffortCap(asked: route, answeredBy: $0)
                                    })
            var summary = speaksAnswer ? SpokenSummary() : nil
            var firstAudio: OSSignpostIntervalState?
            for try await chunk in stream {
                if let state = waitingForFirstToken {
                    Signposts.signposter.endInterval("Domanda, primo token", state)
                    waitingForFirstToken = nil
                    if let step = route.step(answeredBy: nil) {
                        firstTokens[RetryAlternative(target: .claude(step)).id] = ContinuousClock.now - started
                    }
                    intake.beginWorking(on: submission)
                    if speaksAnswer { firstAudio = Signposts.beginInterval(.voiceFirstAudio) }
                }
                answer += summary?.read(chunk) ?? chunk
                if let line = summary?.line {
                    summary = nil
                    say(line, for: submission, firstAudio: firstAudio)
                }
            }
            if var summary {
                answer += summary.finish()
                if let line = summary.line { say(line, for: submission, firstAudio: firstAudio) }
            }
        } catch is CancellationError {
        } catch let failure as QuestionFailure {
            self.failure = failure
        } catch let error as AgentBridgeError {
            Logger.agent.error("Domanda failed: \(String(describing: error), privacy: .public)")
            // With no network `claude` gives up with a generic error: say why instead.
            if case .failed = error, !(await cli.isOnline()) {
                failure = .offline
            } else {
                failure = .bridge(error)
            }
        } catch {
            Logger.agent.error("Domanda failed: \(error)")
            failure = .unexpected
        }
    }

    /// Says `line`, the Sintesi parlata of `submission`'s answer, with the Orb in Parla and the line as subtitles.
    ///
    /// - Parameter firstAudio: The interval from the first text of the answer, which the first audio ends.
    private func say(_ line: String, for submission: IntakePipeline.Submission, firstAudio: OSSignpostIntervalState?) {
        speaking?.cancel()
        subtitle = line
        intake.beginSpeaking(on: submission)
        if speaker.hasOnlyDefaultVoices, !defaults.bool(forKey: Self.betterVoiceDismissedKey) { invitesBetterVoice = true }
        speaking = Task { [speaker, orb, intake] in
            var firstAudio = firstAudio
            await speaker.speak(line) { level in
                if let state = firstAudio {
                    Signposts.endInterval(.voiceFirstAudio, state)
                    firstAudio = nil
                }
                orb.voiceLevel = level
            }
            intake.endSpeaking(on: submission)
            if !Task.isCancelled { subtitle = nil }
        }
    }

    /// Remembers the effort the SDK lowered `asked`'s to, as the strongest its family accepts.
    private func learnEffortCap(asked route: Route, answeredBy answeringModel: AnsweringModel) {
        guard let family = route.family, ModelFamily(model: answeringModel.model) == family,
              let wanted = route.effort, let effective = answeringModel.effort, effective < wanted
        else { return }
        effortCaps[family] = min(effortCaps[family] ?? effective, effective)
    }

    /// Starts the bridge without asking anything, so the first Domanda or Sessione finds it ready.
    func startBridge() async {
        do {
            try await readyBridge().start()
        } catch {
            Logger.agent.notice("Bridge not started: \(String(describing: error), privacy: .public)")
        }
    }

    /// The bridge to `claude`, started on first use and shared with the Sessioni.
    func readyBridge() async throws -> AgentBridge {
        if let bridge { return bridge }
        guard let claude = await cli.executableURL() else { throw QuestionFailure.claudeMissing }
        // The key is read only once the user chose it, and goes only into the bridge's environment.
        let key = try await usesAPIKey ? apiKey() : nil
        // The bridge's start, the Quota read and a Domanda can all get here across the awaits: keep one bridge.
        if let bridge { return bridge }
        let bridge = AgentBridge(executable: bridgeExecutable, arguments: bridgeArguments,
                                 environment: ChildEnvironment.make(claude: claude, apiKey: key,
                                                                    conversations: try? ConversationStore.defaultFile()),
                                 quota: { [weak self] reported in
                                     guard let self else { return }
                                     hasFreshQuota = true
                                     quotaReports += 1
                                     quota = quota.merging(reported)
                                     quota.save(to: defaults)
                                 },
                                 catalog: { [weak self] in self?.catalog = $0 },
                                 remember: { [weak self] text, title in
                                     await self?.remember(text, titled: title) ?? "Bubo non è disponibile."
                                 }) { [index] query, project, source in
            await index?.toolResult(for: query, project: project, source: source) ?? "L'Indice non è disponibile."
        }
        self.bridge = bridge
        return bridge
    }

    /// Saves a note for the `ricorda` tool, and returns what the tool answers `claude`.
    func remember(_ text: String, titled title: String) async -> String {
        do {
            guard let note = try await secondBrain?.remember(text, titled: title) else {
                return "Nota non salvata: l'utente non ha scelto il Secondo cervello. Digli di sceglierlo in "
                    + "Impostazioni › Generale › Secondo cervello."
            }
            savedNote = note.file
            return "Nota salvata nel Secondo cervello: Bubo/Note/\(note.file.lastPathComponent)"
        } catch NoteWriter.Failure.unreachable {
            return "Nota non salvata: la cartella del Secondo cervello non è raggiungibile (disco scollegato o "
                + "cartella spostata)."
        } catch {
            Logger.index.error("Note not saved: \(error)")
            return "Nota non salvata: Bubo non è riuscito a scriverla."
        }
    }

    /// Where Domande run: they have no Progetto, so an empty folder of Bubo's own.
    private static func directory() throws -> URL {
        let directory = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Bubo/Domande", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
