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
    /// A Sessione that was in Lavora when Bubo quit is Ferma: nothing resumes on its own.
    init(file: URL, worktrees: WorktreeManager, bridge: @escaping () async throws -> AgentBridge) {
        self.file = file
        self.worktrees = worktrees
        self.bridge = bridge
        do {
            sessions = try JSONDecoder().decode([Session].self, from: Data(contentsOf: file))
        } catch CocoaError.fileReadNoSuchFile {
        } catch {
            Logger.sessions.error("Sessioni unreadable: \(error)")
        }
        for index in sessions.indices where sessions[index].activity == .lavora {
            sessions[index].activity = .ferma
        }
    }

    @ObservationIgnored private let file: URL
    @ObservationIgnored private let worktrees: WorktreeManager
    @ObservationIgnored private let bridge: () async throws -> AgentBridge
    @ObservationIgnored private let ports = PortAllocator()

    /// The store in Bubo's Application Support folder.
    static func makeDefault(bridge: @escaping () async throws -> AgentBridge) throws -> SessionStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return SessionStore(file: support.appending(path: "Bubo/Sessioni.json"), worktrees: try .makeDefault(),
                            bridge: bridge)
    }

    /// Starts a Sessione titled `title` on `project`: prepares its copy on `branch`, then asks `claude` `prompt` there.
    func start(_ prompt: String, title: String, branch: String, in project: URL) {
        var session = Session(id: UUID(), title: title, project: project)
        session.ports = ports.ports(avoiding: sessions.compactMap(\.ports))
        Signposts.signposter.withIntervalSignpost("Apertura Sessione") {
            sessions.append(session)
            save()
        }
        Task { await run(session.id, prompt: prompt, branch: branch) }
    }

    private func run(_ id: UUID, prompt: String, branch: String) async {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        let environment = session.portEnvironment
        do {
            let preparing = Signposts.signposter.beginInterval("Sessione pronta", id: Signposts.signposter.makeSignpostID())
            let workspace = try await worktrees.prepare(session.project, branch: branch)
            Signposts.signposter.endInterval("Sessione pronta", preparing)
            update(id) { $0.workspace = workspace }
            if let failure = await worktrees.runSetup(in: workspace, environment: environment) {
                update(id) { $0.setupFailure = failure }
            }
            for try await _ in try await bridge().ask(prompt, in: workspace.folder, environment: environment) {}
            update(id) { $0.activity = .ferma }
        } catch {
            Logger.sessions.error("Sessione failed: \(String(describing: error), privacy: .private)")
            update(id) { session in
                session.activity = .errore
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
