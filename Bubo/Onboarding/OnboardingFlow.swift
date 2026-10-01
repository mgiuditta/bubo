import Foundation
import os

/// The first launch in the HUD (spec 26): the Orb asks for a Progetto and a question, in either order, and the first
/// Sessione starts as soon as both are there and `claude` is ready.
///
/// The question waits across launches until the first token of the answer, which ends the onboarding for good.
@Observable
final class OnboardingFlow {
    /// The `UserDefaults` key of whether the onboarding is over.
    static let completedKey = "onboardingCompleted"
    /// The `UserDefaults` key of the question waiting for its Sessione.
    static let pendingQuestionKey = "onboardingPendingQuestion"

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
    ///   - moveToAPIKey: Moves the Sessioni to the API key saved in the keychain.
    ///   - moveToSubscription: Moves the Sessioni back to the login of `claude`.
    ///   - firstTokenTimeout: How long the first Sessione may go without its first token.
    ///   - sleep: Waits for a duration: the clock of `firstTokenTimeout`.
    ///   - isOnline: Whether the Mac can reach the network.
    ///   - restart: Asks the first question again in its Sessione.
    ///   - start: Starts the first Sessione with the question in the Progetto, returning its id.
    init(hasSessions: Bool, defaults: UserDefaults = .standard, checkInterval: Duration = .seconds(1),
         detect: @escaping () async -> ClaudeReadiness = { await ClaudeReadiness.detect() },
         moveToAPIKey: @escaping () -> Void = {},
         moveToSubscription: @escaping () -> Void = {},
         firstTokenTimeout: Duration = .seconds(30),
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         isOnline: @escaping () async -> Bool = { await NetworkStatus.isOnline() },
         restart: @escaping (_ session: UUID) -> Void = { _ in },
         start: @escaping (_ question: String, _ project: URL) throws -> UUID) {
        self.defaults = defaults
        self.checkInterval = checkInterval
        self.detect = detect
        self.moveToAPIKey = moveToAPIKey
        self.moveToSubscription = moveToSubscription
        self.firstTokenTimeout = firstTokenTimeout
        self.sleep = sleep
        self.isOnline = isOnline
        self.restart = restart
        self.start = start
        pendingQuestion = defaults.string(forKey: Self.pendingQuestionKey)
        isCompleted = defaults.bool(forKey: Self.completedKey)
        if hasSessions && pendingQuestion == nil && !isCompleted { complete() }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let start: (String, URL) throws -> UUID
    @ObservationIgnored private let checkInterval: Duration
    @ObservationIgnored private let detect: () async -> ClaudeReadiness
    @ObservationIgnored private let moveToAPIKey: () -> Void
    @ObservationIgnored private let moveToSubscription: () -> Void
    @ObservationIgnored private let firstTokenTimeout: Duration
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    @ObservationIgnored private let isOnline: () async -> Bool
    @ObservationIgnored private let restart: (UUID) -> Void
    /// The first Sessione, once started in this launch.
    @ObservationIgnored private var session: UUID?
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
        if readiness == nil { return "Controllo cosa c'è sul Mac…" }
        if pendingQuestion != nil && project == nil { return "In quale Progetto?" }
        return "Su cosa lavoriamo?"
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

    /// Whether `claude` was found not ready: missing, signed out or outdated, with a remedy to show.
    var needsRemedy: Bool {
        readiness != nil && !isClaudeReady
    }

    /// Finds out for the first time whether `claude` can answer.
    func detectClaude() async {
        lastCheck = .now
        readiness = await Signposts.measure(.claudeDetection) { await detect() }
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

    /// Sends what is typed: it waits for the Progetto and for `claude`, or starts the Sessione at once.
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
        guard !hasStarted, let pendingQuestion, let project, case .ready = readiness else { return }
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
