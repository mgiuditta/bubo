import Foundation
import os

/// The Sessioni of every Progetto, kept in a JSON file across launches.
@Observable
final class SessionStore {
    /// The Sessioni, oldest first.
    private(set) var sessions: [Session] = []

    /// The Progetti that have Sessioni, most recent first.
    var projects: [URL] {
        var seen = Set<URL>()
        return sessions.reversed().map(\.project).filter { seen.insert($0).inserted }
    }

    /// Creates a store kept in `file`, preparing copies with `worktrees` and talking to `claude` through `bridge`.
    ///
    /// A Sessione that was in Lavora or Attende te when Bubo quit is Ferma and waits for Riprendi: nothing resumes
    /// on its own. One whose Progetto or worktree is gone is in Errore.
    ///
    /// - Parameter orb: The Orb whose Stato follows the Attività of the Sessioni; `nil` for none.
    init(file: URL, worktrees: WorktreeManager, orb: OrbControls? = nil,
         bridge: @escaping () async throws -> AgentBridge) {
        self.file = file
        self.worktrees = worktrees
        self.orb = orb
        self.bridge = bridge
        do {
            sessions = try JSONDecoder().decode([Session].self, from: Data(contentsOf: file))
        } catch CocoaError.fileReadNoSuchFile {
        } catch {
            Logger.sessions.error("Sessioni unreadable: \(error)")
        }
        for index in sessions.indices {
            if sessions[index].isRunning {
                sessions[index].enter(.ferma)
                sessions[index].isInterrupted = true
            }
            if let failure = Self.missingFolder(of: sessions[index]) {
                sessions[index].enter(.errore)
                sessions[index].failure = failure
            }
        }
    }

    @ObservationIgnored private let file: URL
    @ObservationIgnored private let worktrees: WorktreeManager
    @ObservationIgnored private let orb: OrbControls?
    @ObservationIgnored private let bridge: () async throws -> AgentBridge
    @ObservationIgnored private let ports = PortAllocator()

    /// The store in Bubo's Application Support folder.
    static func makeDefault(bridge: @escaping () async throws -> AgentBridge) throws -> SessionStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return SessionStore(file: support.appending(path: "Bubo/Sessioni.json"), worktrees: try .makeDefault(),
                            orb: .shared, bridge: bridge)
    }

    /// The configuration `claude` loads in `project`, read through the Sessioni's bridge without spending Quota.
    func configuration(of project: URL) async throws -> ClaudeConfiguration {
        try await bridge().configuration(of: project)
    }

    /// The Cronologia CLI, most recent first: the 50 most recent, or all of it when `isComplete`.
    func history(isComplete: Bool = false) async throws -> [CLIConversation] {
        try await Signposts.measure(.cliHistory) { try await bridge().history(isComplete: isComplete) }
    }

    /// The latest messages of a Cronologia CLI conversation, oldest first.
    func transcript(of conversation: CLIConversation) async throws -> [CLIConversation.Message] {
        try await bridge().transcript(of: conversation.id)
    }

    /// Starts a Sessione titled `title` on `project`: prepares its copy on `branch`, then asks `claude` `prompt` there.
    ///
    /// - Parameters:
    ///   - onCheckout: Whether the Sessione works on the Progetto's checkout, with no copy of its own.
    ///   - conversation: The Cronologia CLI conversation the Sessione continues, as a fork.
    /// - Throws: `SessionError.checkoutTaken` when `onCheckout` and another open Sessione already works there.
    func start(_ prompt: String, title: String, branch: String, in project: URL, onCheckout: Bool = false,
               forkingFrom conversation: CLIConversation? = nil) throws {
        if onCheckout, let taken = checkoutSession(of: project) { throw SessionError.checkoutTaken(by: taken.title) }
        var session = Session(id: UUID(), title: title, project: project, activitySince: .now)
        session.prompt = prompt
        session.forkedFrom = conversation?.id
        if onCheckout {
            session.isOnCheckout = true
            session.workspace = Workspace(folder: project)
        }
        session.ports = ports.ports(avoiding: sessions.compactMap(\.ports))
        Signposts.signposter.withIntervalSignpost("Apertura Sessione") {
            sessions.append(session)
            save()
        }
        followActivity()
        Task { await run(session.id, prompt: prompt, branch: branch) }
    }

    /// The open Sessione that works on the checkout of `project`, if any.
    func checkoutSession(of project: URL) -> Session? {
        sessions.first { session in
            session.isOnCheckout && session.phase == .aperta
                && session.project.standardizedFileURL.path == project.standardizedFileURL.path
        }
    }

    /// Asks `claude` again, in the same worktree, the prompt of a Sessione that Bubo's quitting interrupted.
    // ponytail: the same prompt in a new Conversazione; the SDK's `resume` comes with #159.
    func resume(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }), session.isInterrupted, let prompt = session.prompt
        else { return }
        update(id) { session in
            session.enter(.lavora)
            session.summary = nil
            session.isInterrupted = false
        }
        Task { await run(id, prompt: prompt, branch: Session.proposedBranch(for: session.title)) }
    }

    /// Archives a Sessione: its worktree goes in the background, its branch stays, its ports are free again.
    func archive(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }), session.phase == .aperta, !session.isRunning
        else { return }
        update(id) { session in
            session.phase = .archiviata
            session.ports = nil
            session.isInterrupted = false
        }
        guard let workspace = session.workspace else { return }
        Task { await worktrees.remove(workspace, of: session.project, deletingBranch: false) }
    }

    /// What deleting the Sessione `id` would lose, as file paths and commit subjects.
    func lostChanges(_ id: UUID) async -> [String] {
        guard let session = sessions.first(where: { $0.id == id }), let workspace = session.workspace else { return [] }
        return await worktrees.lostChanges(in: workspace, of: session.project)
    }

    /// Deletes a Sessione with its worktree and its branch, in the background.
    func delete(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }), !session.isRunning else { return }
        sessions.removeAll { $0.id == id }
        save()
        followActivity()
        guard let workspace = session.workspace else { return }
        Task { await worktrees.remove(workspace, of: session.project, deletingBranch: true) }
    }

    /// Why an open Sessione cannot work any more: its Progetto or its worktree is gone.
    private static func missingFolder(of session: Session) -> String? {
        guard session.phase == .aperta else { return nil }
        if !FileManager.default.fileExists(atPath: session.project.path) {
            return String(localized: "Il Progetto non è più in \(session.project.path). Riporta lì la cartella o cancella la Sessione.")
        }
        if let workspace = session.workspace, workspace.branch != nil,
           !FileManager.default.fileExists(atPath: workspace.folder.path) {
            return String(localized: "La copia isolata della Sessione non è più in \(workspace.folder.path). Cancella la Sessione per toglierla dall'elenco.")
        }
        return nil
    }

    /// Prepares the Sessione's copy on `branch` if it has none yet, then asks `claude` `prompt` there.
    private func run(_ id: UUID, prompt: String, branch: String) async {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        let environment = session.portEnvironment
        do {
            let workspace: Workspace
            if let prepared = session.workspace {
                workspace = prepared
            } else {
                let preparing = Signposts.signposter.beginInterval("Sessione pronta",
                                                                   id: Signposts.signposter.makeSignpostID())
                workspace = try await worktrees.prepare(session.project, branch: branch)
                Signposts.signposter.endInterval("Sessione pronta", preparing)
                update(id) { $0.workspace = workspace }
                if let failure = await worktrees.runSetup(in: workspace, environment: environment) {
                    update(id) { $0.setupFailure = failure }
                }
            }
            let answer = try await bridge().ask(prompt, in: workspace.folder, environment: environment,
                                                forkingFrom: session.forkedFrom) { [weak self] progress in
                self?.update(id) { $0.apply(progress) }
            }
            for try await _ in answer {}
            update(id) { $0.enter(.ferma) }
        } catch {
            Logger.sessions.error("Sessione failed: \(String(describing: error), privacy: .private)")
            update(id) { session in
                session.enter(.errore)
                session.failure = switch error {
                case let WorktreeError.git(message): message.trimmingCharacters(in: .whitespacesAndNewlines)
                case let AgentBridgeError.failed(message): message
                // ponytail: the three choices at the limit are in the Domanda; the Sessione says only why it stopped.
                case AgentBridgeError.limitReached: String(localized: "Hai raggiunto il limite dell'abbonamento.")
                case AgentBridgeError.signInRequired: String(localized: "L'accesso a Claude è scaduto.")
                case QuestionFailure.claudeMissing: String(localized: "Claude Code non trovato: installa la CLI claude.")
                default: String(localized: "Il collegamento con Claude si è interrotto.")
                }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout Session) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[index])
        save()
        followActivity()
    }

    /// Gives the Orb the Stato of the Sessioni's Attività.
    private func followActivity() {
        let state = OrbState(following: sessions)
        if orb?.state != state { orb?.state = state }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(sessions).write(to: file, options: .atomic)
        } catch {
            Logger.sessions.error("Sessioni not saved: \(error)")
        }
    }
}

/// Why a Sessione cannot start.
nonisolated enum SessionError: LocalizedError, Equatable {
    /// Another open Sessione, with this title, already works on the Progetto's checkout.
    case checkoutTaken(by: String)

    var errorDescription: String? {
        switch self {
        case let .checkoutTaken(title):
            String(localized: "«\(title)» lavora già sul checkout di questo Progetto. Archiviala, o lavora in una copia isolata.")
        }
    }
}

extension OrbState {
    /// The Stato for these Sessioni: Ascolto while an open one is in Attende te, since it waits for the user;
    /// Lavora while one works; Riposo otherwise.
    // ponytail: the HUD has no Sessione in front of the user yet; then the Stato follows that one alone.
    init(following sessions: [Session]) {
        let open = sessions.filter { $0.phase == .aperta }
        if open.contains(where: { $0.activity == .attende }) {
            self = .listening
        } else if open.contains(where: { $0.activity == .lavora }) {
            self = .working
        } else {
            self = .idle
        }
    }
}
