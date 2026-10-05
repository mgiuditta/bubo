import Foundation
import os

/// The first launch in the HUD (spec 26): the Orb asks for the Motore (ADR 0014), then for a Progetto and a question,
/// in either order, and the first Sessione starts as soon as both are there and the Motore principale is ready.
///
/// The question waits across launches until the first token of the answer, which ends the onboarding for good.
@Observable
final class OnboardingFlow {
    /// The `UserDefaults` key of whether the onboarding is over.
    static let completedKey = "onboardingCompleted"
    /// The `UserDefaults` key of the question waiting for its Sessione.
    static let pendingQuestionKey = "onboardingPendingQuestion"
    /// The `UserDefaults` key of whether the user answered the first Richiesta di permesso in the HUD.
    static let firstPermissionAnsweredKey = "onboardingFirstPermissionAnswered"
    /// The `UserDefaults` key of whether the user chose the Motore: the step does not come back after a quit.
    static let engineChosenKey = "onboardingEngineChosen"

    /// The steps shown under the Orb, in order: the Motore, the Progetto, then the question.
    enum Step: CaseIterable {
        case engine
        case project
        case question
    }

    /// What the user can choose at the step of the Motore (ADR 0014).
    enum EngineOption: CaseIterable {
        case claude
        case copilot
        /// Both Motori: the principale, and the other as the Riserva.
        case both

        /// The Motori that must be ready for this option.
        var engines: [Session.Engine] {
            switch self {
            case .claude: [.claude]
            case .copilot: [.copilot]
            case .both: [.claude, .copilot]
            }
        }
    }

    /// The three questions offered under the input bar.
    static let suggestions: [LocalizedStringResource] = [
        "Spiegami com'è fatto questo Progetto",
        "Trova i TODO più vecchi",
        "Cosa è cambiato nell'ultima settimana?",
    ]

    /// Whether the first answer arrived: from then on the onboarding never shows again.
    private(set) var isCompleted: Bool
    /// The question sent before the Progetto was chosen or `claude` was found, kept until the first token.
    private(set) var pendingQuestion: String?
    /// The Progetto chosen for the first Sessione.
    private(set) var project: URL?
    /// The recent Progetti offered; empty until loaded.
    private(set) var recents: [RecentProject] = []
    /// The `claude` that will answer; `nil` while detecting. Signed out counts as ready once the user chose the API key.
    /// After the onboarding it stays `nil` until a Sessione finds `claude` too old (spec 27).
    var readiness: ClaudeReadiness? {
        didSet {
            if usesAPIKey, case let .signedOut(version) = readiness { readiness = .ready(version: version, method: "API key") }
            startIfReady()
            if case .ready = readiness, oldValue != readiness { onClaudeReady() }
        }
    }
    /// The `copilot` that can answer in place of `claude`; `nil` until detected at launch (#719).
    var copilotReadiness: CopilotReadiness? {
        didSet { startIfReady() }
    }
    /// The card chosen at the step of the Motore; `nil` until the user, or the detection of a single Motore, picks one.
    private(set) var engineOption: EngineOption?
    /// With ``EngineOption/both``, the Motore principale: the other one is the Riserva.
    var primaryOfBoth: Session.Engine = .claude
    /// Whether the step of the Motore is behind: the Motore principale is saved.
    private(set) var isEngineChosen: Bool
    /// Whether ``recheckEngines()`` is asking `claude` and `copilot` again.
    private(set) var isRecheckingEngines = false
    /// Called each time `claude` becomes ready: the Sessioni waiting for it start.
    @ObservationIgnored var onClaudeReady: () -> Void = {}
    /// Whether the user chose to answer with the API key, until Bubo quits.
    private(set) var usesAPIKey = false
    /// What the user is typing in the input bar.
    var draft = ""
    /// Why the first Sessione has not answered yet, with the remedy to show; `nil` while it may still answer.
    private(set) var problem: Problem?
    /// Whether the user went to sign in from a remedy: the first question asks again when they are back.
    private(set) var isAwaitingSignIn = false
    /// Whether the first Richiesta di permesso was answered from the HUD: later ones stay in their Sessione.
    private(set) var isFirstPermissionAnswered: Bool

    /// Why the first turn did not answer (spec 26).
    enum Problem: Equatable {
        /// The credential or the network failed.
        case failed(AuthFailure)
        /// No first token within `firstTokenTimeout`.
        case unanswered
    }

    /// Creates the flow, finished already when the user has Sessioni of their own.
    ///
    /// - Parameters:
    ///   - hasSessions: Whether a Sessione exists. With no question waiting the user is past the onboarding; with one,
    ///     Bubo quit during the first turn and the onboarding lasts until that Sessione answers.
    ///   - defaults: Where the flow keeps its state.
    ///   - checkInterval: The shortest time between two checks of `claude`.
    ///   - detect: Finds out whether `claude` can answer.
    ///   - detectCopilot: Finds out whether `copilot` can answer.
    ///   - moveToAPIKey: Moves the Sessioni to the API key saved in the keychain.
    ///   - moveToSubscription: Moves the Sessioni back to the login of `claude`.
    ///   - firstTokenTimeout: How long the first Sessione may go without its first token.
    ///   - sleep: Waits for a duration: the clock of `firstTokenTimeout`.
    ///   - isOnline: Whether the Mac can reach the network.
    ///   - restart: Asks the first question again in its Sessione.
    ///   - settings: Where Copilot's consent is kept.
    ///   - start: Starts the first Sessione with the question in the Progetto, on the Motore principale saved in
    ///     `defaults`, returning its id.
    init(hasSessions: Bool, defaults: UserDefaults = .standard, checkInterval: Duration = .seconds(1),
         detect: @escaping () async -> ClaudeReadiness = { await ClaudeReadiness.detect() },
         detectCopilot: @escaping @Sendable () async -> CopilotReadiness = { await CopilotReadiness.detect() },
         moveToAPIKey: @escaping () -> Void = {},
         moveToSubscription: @escaping () -> Void = {},
         firstTokenTimeout: Duration = .seconds(30),
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         isOnline: @escaping () async -> Bool = { await NetworkStatus.isOnline() },
         restart: @escaping (_ session: UUID) -> Void = { _ in },
         settings: EndpointSettings = .shared,
         start: @escaping (_ question: String, _ project: URL) throws -> UUID) {
        self.defaults = defaults
        self.checkInterval = checkInterval
        self.detect = detect
        self.detectCopilot = detectCopilot
        self.moveToAPIKey = moveToAPIKey
        self.moveToSubscription = moveToSubscription
        self.firstTokenTimeout = firstTokenTimeout
        self.sleep = sleep
        self.isOnline = isOnline
        self.restart = restart
        self.settings = settings
        self.start = start
        pendingQuestion = defaults.string(forKey: Self.pendingQuestionKey)
        let isCompleted = defaults.bool(forKey: Self.completedKey)
        self.isCompleted = isCompleted
        isFirstPermissionAnswered = defaults.bool(forKey: Self.firstPermissionAnsweredKey)
        // Who used Bubo before the step, or already started the first Sessione, stays on the Motore saved (ADR 0014).
        isEngineChosen = defaults.bool(forKey: Self.engineChosenKey) || isCompleted || hasSessions
        if hasSessions && pendingQuestion == nil && !isCompleted { complete() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let start: (String, URL) throws -> UUID
    @ObservationIgnored private let checkInterval: Duration
    @ObservationIgnored private let detect: () async -> ClaudeReadiness
    @ObservationIgnored private let detectCopilot: @Sendable () async -> CopilotReadiness
    @ObservationIgnored private let moveToAPIKey: () -> Void
    @ObservationIgnored private let moveToSubscription: () -> Void
    @ObservationIgnored private let firstTokenTimeout: Duration
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    @ObservationIgnored private let isOnline: () async -> Bool
    @ObservationIgnored private let restart: (UUID) -> Void
    private let settings: EndpointSettings
    /// The first Sessione, once started in this launch.
    private var session: UUID?
    /// Waits for the first token of the first Sessione, up to `firstTokenTimeout`.
    @ObservationIgnored private var firstTokenWait: Task<Void, Never>?
    /// When the last check of `claude` started.
    @ObservationIgnored private var lastCheck: ContinuousClock.Instant?
    @ObservationIgnored private var isChecking = false
    /// Whether something changed during a check, which then runs again.
    @ObservationIgnored private var needsCheck = false
    /// Whether the first Sessione started in this launch.
    private var hasStarted: Bool { session != nil }

    /// What the Orb says now.
    var orbLine: LocalizedStringResource {
        if !isEngineChosen { return "Con quale Motore lavoriamo?" }
        if isDetectingPrimaryEngine { return "Controllo cosa c'è sul Mac…" }
        if pendingQuestion != nil && project == nil { return "In quale Progetto?" }
        return "Su cosa lavoriamo?"
    }

    /// Whether `step` is done: a Progetto chosen, or a question sent.
    func isDone(_ step: Step) -> Bool {
        switch step {
        case .engine: isEngineChosen
        case .project: project != nil
        case .question: pendingQuestion != nil || hasStarted
        }
    }

    /// The step the user should do next, once the other one is under way; `nil` before anything or when both are
    /// done.
    ///
    /// A question typed or sent with no Progetto highlights the Progetto, so the user sees what is missing.
    var highlightedStep: Step? {
        if !isEngineChosen { return .engine }
        let isTyping = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !isDone(.project) { return isDone(.question) || isTyping ? .project : nil }
        return isDone(.question) ? nil : .question
    }

    /// The first Sessione, while its first Richiesta di permesso is to be answered from the centre of the HUD.
    var sessionAwaitingFirstPermission: UUID? {
        isFirstPermissionAnswered ? nil : session
    }

    /// The user answered the first Richiesta di permesso: the next ones stay in their Sessione.
    func answerFirstPermission() {
        isFirstPermissionAnswered = true
        defaults.set(true, forKey: Self.firstPermissionAnsweredKey)
    }

    /// Whether `claude` was found and can answer.
    var isClaudeReady: Bool {
        if case .ready = readiness { true } else { false }
    }

    /// Whether `claude` answers with an API key: Bubo's, or one in the user's settings.
    private var answersWithAPIKey: Bool {
        if usesAPIKey { return true }
        if case .ready(_, "API key") = readiness { return true }
        return false
    }

    /// Whether `claude` was found not ready while Bubo needs it, with a remedy to show: missing, signed out or outdated
    /// with Claude as the Motore principale, or too old for a Sessione that runs on it.
    var needsRemedy: Bool {
        guard let readiness, !isClaudeReady else { return false }
        if case .outdated = readiness { return true }
        return primaryEngine == .claude
    }

    /// The Motore the first Sessione starts on and the input bar names: the one of the card chosen, then the one
    /// saved.
    var primaryEngine: Session.Engine {
        guard !isEngineChosen, let engineOption else { return PrimaryEngine.saved(in: defaults).engine }
        return switch engineOption {
        case .claude: .claude
        case .copilot: .copilot
        case .both: primaryOfBoth
        }
    }

    /// Whether Bubo is still finding out whether the Motore principale can answer.
    var isDetectingPrimaryEngine: Bool {
        switch primaryEngine {
        case .claude: readiness == nil
        case .copilot: copilotReadiness == nil
        }
    }

    /// Whether `engine` was found on the Mac, ready or not.
    func isFound(_ engine: Session.Engine) -> Bool {
        switch engine {
        case .claude: readiness.map { $0 != .missing } ?? false
        case .copilot: copilotReadiness.map { $0 != .missing } ?? false
        }
    }

    /// Whether `engine` can answer now.
    func isReady(_ engine: Session.Engine) -> Bool {
        switch engine {
        case .claude: isClaudeReady
        case .copilot: if case .ready = copilotReadiness { true } else { false }
        }
    }

    /// Whether every Motore of `option` can answer now.
    func isReady(option: EngineOption) -> Bool {
        option.engines.allSatisfy(isReady)
    }

    /// Whether the card chosen includes Copilot and the user has not allowed it yet: the step asks before going on.
    var needsCopilotConsent: Bool {
        engineOption != nil && engineOption != .claude && !settings.allowsCopilot
    }

    /// Whether the step of the Motore can end: a card chosen, its Motori ready, and Copilot allowed if it is there.
    var canConfirmEngine: Bool {
        guard let engineOption, !isEngineChosen else { return false }
        return isReady(option: engineOption) && !needsCopilotConsent
    }

    /// Chooses `option` at the step of the Motore.
    func chooseEngine(_ option: EngineOption) {
        guard !isEngineChosen else { return }
        engineOption = option
    }

    /// The user allows Copilot to receive Domande and the files of the Progetti, and, when `sharesNotes`, the notes of
    /// the Secondo cervello: asked here, never again at the first Domanda.
    func allowCopilot(sharingNotes sharesNotes: Bool) {
        settings.grantCopilotConsent()
        settings.answerCopilotNotesConsent(allowing: sharesNotes)
    }

    /// Ends the step of the Motore: saves the Motore principale, with the Riserva when both were chosen, and goes on
    /// to the Progetto.
    func confirmEngine() {
        guard canConfirmEngine, let engineOption else { return }
        defaults.set(primaryEngine.rawValue, forKey: PrimaryEngine.engineKey)
        defaults.set(engineOption == .both, forKey: PrimaryEngine.reserveKey)
        defaults.set(true, forKey: Self.engineChosenKey)
        isEngineChosen = true
        startIfReady()
    }

    /// Asks `claude` and `copilot` again, both at once: «Riprova» on a card of the step.
    func recheckEngines() async {
        guard !isRecheckingEngines else { return }
        isRecheckingEngines = true
        defer { isRecheckingEngines = false }
        await detectEngines()
    }

    /// Preselects the only Motore found, when the user has not chosen yet.
    private func preselectEngine() {
        guard engineOption == nil, !isEngineChosen else { return }
        switch (isFound(.claude), isFound(.copilot)) {
        case (true, false): engineOption = .claude
        case (false, true): engineOption = .copilot
        default: break
        }
    }

    /// Finds out for the first time whether `claude` can answer.
    func detectClaude() async {
        lastCheck = .now
        readiness = await Signposts.measure(.claudeDetection) { await detect() }
    }

    /// Finds out at launch whether `claude` and `copilot` can answer, both at once (#719).
    func detectEngines() async {
        async let copilot = detectCopilot()
        await detectClaude()
        copilotReadiness = await copilot
        preselectEngine()
    }

    /// Checks `claude` again while it is not ready, at most once per `checkInterval`.
    ///
    /// A call during a check runs one more check when it ends, so a change in the middle is not missed.
    ///
    /// Back from signing in, asks the first question again instead.
    func recheck() async {
        if isAwaitingSignIn {
            askAgain()
            return
        }
        guard needsRemedy else { return }
        guard !isChecking else {
            needsCheck = true
            return
        }
        isChecking = true
        defer { isChecking = false }
        repeat {
            needsCheck = false
            if let lastCheck { try? await Task.sleep(until: lastCheck + checkInterval) }
            guard !Task.isCancelled else { return }
            lastCheck = .now
            readiness = await detect()
        } while needsCheck && needsRemedy
    }

    /// Answers with the API key the user saved: `claude` no longer needs its own login.
    ///
    /// Called only when the user chooses it (ADR 0003).
    func useAPIKey() async {
        moveToAPIKey()
        usesAPIKey = true
        let readiness = readiness
        self.readiness = readiness
        if problem != nil { askAgain() }
    }

    /// The user goes to sign in from a remedy, leaving the API key if Bubo used one: the first question asks again
    /// at the next `recheck()`.
    func signInAgain() {
        if usesAPIKey {
            moveToSubscription()
            usesAPIKey = false
        }
        isAwaitingSignIn = true
    }

    /// Asks the first question again in the same Sessione, with a new Conversazione: Riprova, or a remedy done.
    func askAgain() {
        guard let session, !isCompleted else { return }
        problem = nil
        isAwaitingSignIn = false
        restart(session)
        waitForFirstToken()
    }

    /// A turn of the Sessione `session` failed with `error`: a remedy, when the error has one and the onboarding is
    /// still waiting for the first answer.
    ///
    /// Any other error leaves the wait for the first token running, so it ends with Riprova and Diagnostica.
    func receiveFailure(_ error: any Error, in session: UUID) {
        guard session == self.session, !isCompleted,
              let failure = AuthFailure(error, usesAPIKey: answersWithAPIKey)
        else { return }
        Logger.sessions.notice("First turn failed: \(String(describing: failure), privacy: .public)")
        firstTokenWait?.cancel()
        problem = .failed(failure)
    }

    /// Shows `recents` as the Progetti to choose from.
    func show(_ recents: [RecentProject]) {
        self.recents = recents
    }

    /// Sends what is typed: it waits for the Progetto and for the Motore, or starts the Sessione at once.
    func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !hasStarted else { return }
        draft = ""
        pendingQuestion = question
        defaults.set(question, forKey: Self.pendingQuestionKey)
        startIfReady()
    }

    /// Chooses `project` for the first Sessione, starting it if a question waits.
    func choose(_ project: URL) {
        guard !hasStarted else { return }
        self.project = project
        startIfReady()
    }

    /// Ends the first launch without a Sessione («Chiedi senza Progetto»): the home shows the Domanda instead.
    func skip() {
        firstTokenWait?.cancel()
        complete()
    }

    /// The first token of a Sessione's answer arrived: the onboarding is over.
    func receiveFirstToken() {
        guard !isCompleted else { return }
        Signposts.emit(.onboardingFirstToken)
        firstTokenWait?.cancel()
        problem = nil
        isAwaitingSignIn = false
        complete()
    }

    private func startIfReady() {
        guard !hasStarted, isEngineChosen, let pendingQuestion, let project, isReady(primaryEngine) else { return }
        do {
            session = try start(pendingQuestion, project)
            waitForFirstToken()
        } catch {
            Logger.sessions.error("First Sessione not started: \(String(describing: error), privacy: .public)")
        }
    }

    /// Shows "Claude non risponde", or "Sei offline" without a network, if the first token is not there in time.
    private func waitForFirstToken() {
        firstTokenWait?.cancel()
        firstTokenWait = Task { [weak self, sleep, firstTokenTimeout] in
            guard (try? await sleep(firstTokenTimeout)) != nil, let self, !Task.isCancelled else { return }
            let isOnline = await self.isOnline()
            guard !Task.isCancelled, !isCompleted, problem == nil else { return }
            problem = isOnline ? .unanswered : .failed(.offline)
        }
    }

    private func complete() {
        isCompleted = true
        pendingQuestion = nil
        defaults.set(true, forKey: Self.completedKey)
        defaults.removeObject(forKey: Self.pendingQuestionKey)
    }
}
