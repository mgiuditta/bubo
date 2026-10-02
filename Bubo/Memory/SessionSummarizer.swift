import Foundation
import Observation
import os

/// Writes the Riassunto di Sessione when a Sessione becomes Fusa or Archiviata, or at "Riassumi ora" (spec 13).
///
/// Claude with the light model writes it; without network Apple's on-device model; without either, the Sessione keeps
/// it pending and it is written when the network returns. What the model reads, and what it writes, passes through
/// the `SecretFilter` before reaching the disk.
@Observable
final class SessionSummarizer {
    /// What a Sessione's card says about its summary.
    enum Notice: Equatable {
        /// No Secondo cervello: the user is asked where to save the summaries.
        case needsFolder
        /// No model could write the summary: it waits for the network.
        case waitingForNetwork
        /// The Secondo cervello cannot be reached: the summary waits for it.
        case secondBrainUnreachable
        /// The summary is in the Secondo cervello.
        case saved
    }

    /// Why no summary could be made.
    enum Failure: Error, Equatable {
        /// The Sessione is not there any more.
        case unknownSession
        /// No engine wrote a summary.
        case noEngine
    }

    /// The defaults key of the setting that writes the summaries at Fondi and Archivia; on when absent.
    static let defaultsKey = "sessionSummaries"

    /// The notices of the Sessioni, by id.
    private(set) var notices: [UUID: Notice] = [:]

    @ObservationIgnored private let sessions: SessionStore
    @ObservationIgnored private let secondBrain: SecondBrain
    @ObservationIgnored private let index: SearchIndex?
    @ObservationIgnored private let engines: [any SummaryEngine]
    @ObservationIgnored private let transcript: (String) async throws -> [CLIConversation.Message]
    @ObservationIgnored private let filter: SecretFilter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isOnline: () async -> Bool
    /// The Sessioni being summarized now, and those to summarize again once done.
    @ObservationIgnored private var inFlight: Set<UUID> = []
    @ObservationIgnored private var again: Set<UUID> = []

    private static let signposter = OSSignposter(logger: .memory)

    /// Creates the summarizer of the Sessioni in `sessions`, writing in `secondBrain`.
    ///
    /// - Parameters:
    ///   - index: Where the related notes are searched; `nil` for none.
    ///   - engines: The models, tried in order.
    ///   - transcript: The messages of an agent's conversation, by id.
    ///   - isOnline: Whether the network can be reached now.
    init(sessions: SessionStore, secondBrain: SecondBrain, index: SearchIndex?, engines: [any SummaryEngine],
         transcript: @escaping (String) async throws -> [CLIConversation.Message],
         filter: SecretFilter = SecretFilter(), defaults: UserDefaults = .standard,
         isOnline: @escaping () async -> Bool = { await NetworkStatus.isOnline() }) {
        self.sessions = sessions
        self.secondBrain = secondBrain
        self.index = index
        self.engines = engines
        self.transcript = transcript
        self.filter = filter
        self.defaults = defaults
        self.isOnline = isOnline
        sessions.onPhaseChange = { [weak self] id, _ in
            guard let self, isOn else { return }
            Task { await self.summarize(id) }
        }
    }

    /// Whether the summaries are written at Fondi and Archivia; "Riassumi ora" writes one anyway.
    var isOn: Bool {
        defaults.object(forKey: Self.defaultsKey) as? Bool ?? true
    }

    /// The summary of the Sessione `id`, without writing it: filtered of secrets and within 200 words.
    ///
    /// - Throws: `Failure` when the Sessione is gone or no engine wrote a summary.
    func summary(of id: UUID) async throws -> SessionSummary {
        guard let session = sessions.sessions.first(where: { $0.id == id }) else { throw Failure.unknownSession }
        var messages: [CLIConversation.Message] = []
        for conversation in session.conversations {
            messages += (try? await transcript(conversation)) ?? []
        }
        let input = SummaryInput(session: id, title: session.title, projectName: session.project.lastPathComponent,
                                 branch: session.workspace?.branch, messages: messages).redacted(by: filter)
        var online: Bool?
        for engine in engines {
            if engine.needsNetwork {
                if online == nil { online = await isOnline() }
                guard online == true else { continue }
            }
            do {
                return try await engine.summary(of: input).redacted(by: filter).limited()
            } catch {
                Logger.memory.error("Summary engine failed: \(String(describing: error), privacy: .private)")
            }
        }
        throw Failure.noEngine
    }

    /// Summarizes the Sessione `id` and writes its note; one summary at a time per Sessione, a request during it
    /// summarizes once more at the end.
    func summarize(_ id: UUID) async {
        guard inFlight.insert(id).inserted else {
            again.insert(id)
            return
        }
        defer { inFlight.remove(id) }
        repeat {
            again.remove(id)
            await write(id)
        } while again.contains(id)
    }

    /// Summarizes again the Sessioni whose summary is pending.
    func retryPending() async {
        for session in sessions.sessions where session.isSummaryPending {
            await summarize(session.id)
        }
    }

    /// Summarizes the pending Sessioni each time the network returns, until cancelled.
    func keepRetrying() async {
        var wasOnline = false
        for await isOnline in NetworkStatus.changes() {
            if isOnline && !wasOnline { await retryPending() }
            wasOnline = isOnline
        }
    }

    /// Makes `folder` the Secondo cervello and writes the summaries that waited for it.
    func choose(_ folder: URL) async {
        secondBrain.choose(folder)
        let waiting = notices.filter { $0.value == .needsFolder }.map(\.key)
        for id in waiting {
            notices[id] = nil
            await summarize(id)
        }
    }

    /// "Non salvarli": no summary at Fondi and Archivia from now on, and none for the Sessioni that asked.
    func declineSummaries() {
        defaults.set(false, forKey: Self.defaultsKey)
        notices = notices.filter { $0.value != .needsFolder }
    }

    /// Writes the summary of `id` in `Bubo/Sessioni/`, or keeps it pending with its notice.
    private func write(_ id: UUID) async {
        guard let session = sessions.sessions.first(where: { $0.id == id }) else { return }
        guard secondBrain.location != nil else {
            notices[id] = .needsFolder
            return
        }
        let interval = Self.signposter.beginInterval("Riassunto", id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval("Riassunto", interval) }
        let summary: SessionSummary
        do {
            summary = try await self.summary(of: id)
        } catch {
            Logger.memory.notice("Summary pending: \("no engine", privacy: .public)")
            notices[id] = .waitingForNetwork
            sessions.recordSummary(nil, isPending: true, in: id)
            return
        }
        // The Fase now: the Sessione may have changed while the model wrote.
        let phase = sessions.sessions.first { $0.id == id }?.phase ?? session.phase
        let properties = SummaryProperties(title: session.title, project: session.project.lastPathComponent,
                                           branch: session.workspace?.branch, phase: phase, session: id,
                                           related: await related(to: summary))
        do {
            let note = try await secondBrain.writeSessionSummary(summary.markdown, properties: properties,
                                                                 replacing: session.summaryNote)
            sessions.recordSummary(note, isPending: false, in: id)
            notices[id] = note == nil ? nil : .saved
            Logger.memory.notice("Summary \(note == nil ? "not written, note deleted" : "written", privacy: .public)")
        } catch {
            Logger.memory.notice("Summary pending: \("Secondo cervello unreachable", privacy: .public)")
            notices[id] = .secondBrainUnreachable
            sessions.recordSummary(nil, isPending: true, in: id)
        }
    }

    /// The names of up to three notes of the Secondo cervello about `summary`; the Indice already leaves out `Bubo/`.
    private func related(to summary: SessionSummary) async -> [String] {
        guard let index else { return [] }
        let text = (summary.done + summary.decisions + summary.open).joined(separator: " ")
        let hits = (try? await index.hits(for: text, source: .secondBrain, limit: 6)) ?? []
        var names: [String] = []
        for hit in hits {
            let name = ((hit.path as NSString).lastPathComponent as NSString).deletingPathExtension
            if !names.contains(name) { names.append(name) }
        }
        return Array(names.prefix(3))
    }
}
