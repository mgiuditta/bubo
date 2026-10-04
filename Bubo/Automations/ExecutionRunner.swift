import Foundation
import os

/// Runs the Automazioni: each Esecuzione, by its Ripetizione or by [Avvia ora], is a new Sessione in a new worktree,
/// marked "Automazione", whose turn runs with nobody in front of it (spec 19).
final class ExecutionRunner {
    /// Creates a runner of `automations` in `sessions`; `agentsUser` is the `~/.claude` folder where the user's agents
    /// are.
    init(automations: AutomationStore, sessions: SessionStore, agentsUser: URL = AgentCatalog.userFolder) {
        self.automations = automations
        self.sessions = sessions
        self.agentsUser = agentsUser
    }

    /// The last message the prompt asks for when there is nothing to do: with no changes and no denials, it makes the
    /// Esecuzione Senza modifiche.
    static let nothingToReport = String(localized: "Niente da segnalare.")

    /// Called once an Esecuzione that started has ended, with its Automazione and how it went: the notification of
    /// its result follows it.
    var onFinish: (Automation, Execution) -> Void = { _, _ in }

    /// How many Esecuzioni hold an activity now, against App Nap and idle sleep: none once they end or the Mac sleeps.
    var heldActivities: Int { activities.count }

    private let automations: AutomationStore
    private let sessions: SessionStore
    private let agentsUser: URL
    /// The activity of each Esecuzione at work, by its Sessione.
    private var activities: [UUID: any NSObjectProtocol] = [:]

    /// Starts an Esecuzione of the Automazione `id` now, and records it in its history; or records it Saltata
    /// (sovrapposta) while the same Automazione is still at work, or, outside git, another Sessione works in its
    /// Progetto's folder. When the file of its agent is gone, nothing starts and the Automazione goes in pausa:
    /// `claude` would only warn, and run without the agent.
    ///
    /// - Parameters:
    ///   - scheduledAt: When its Ripetizione had it due; `nil` for [Avvia ora].
    /// - Returns: The id of the Esecuzione's Sessione; `nil` when it did not start or the Automazione is gone.
    @discardableResult
    func run(_ id: Automation.ID, scheduledAt: Date? = nil, at date: Date = .now) -> UUID? {
        guard let automation = automations[id] else { return nil }
        if let agent = automation.agent,
           !AgentCatalog.runnableAgents(in: automation.project, user: agentsUser).contains(agent) {
            automations.pause(id, reason: .agentMissing)
            Logger.automations.notice("Automazione paused: agent missing")
            return nil
        }
        if isOverlapping(automation) {
            automations.record(Execution(startedAt: date, scheduledAt: scheduledAt, outcome: .saltata,
                                         skipReason: .sovrapposta), for: id)
            Logger.automations.notice("Esecuzione skipped: overlapping")
            return nil
        }
        let mark = AutomationMark(automation: id, name: automation.name, startedAt: date)
        let turn = UnattendedTurn(rules: automation.rules, model: automation.model.alias, agent: automation.agent)
        let prompt = Self.prompt(for: automation, scheduledAt: scheduledAt ?? date, startedAt: date)
        let session = sessions.startExecution(prompt, title: automation.name,
                                              branch: Session.proposedBranch(for: "automazione \(automation.name)"),
                                              in: automation.project, automation: mark, unattended: turn,
                                              isAutonomous: automation.isAutonomous) { [weak self] session, succeeded in
            await self?.finish(session, of: id, startedAt: date, scheduledAt: scheduledAt, succeeded: succeeded)
        }
        automations.record(Execution(startedAt: date, scheduledAt: scheduledAt, session: session, outcome: .inCorso),
                           for: id)
        // The finish may already have released it, if the turn ended at once.
        if automations[id]?.lastExecution?.outcome == .inCorso {
            activities[session] = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled], reason: "Esecuzione di un'Automazione")
        }
        Logger.automations.notice("Esecuzione started")
        return session
    }

    /// Makes Interrotta every Esecuzione still in corso whose Sessione no longer works: Bubo quit while it did.
    func markInterrupted() {
        for automation in automations.automations {
            guard var execution = automation.lastExecution, execution.outcome == .inCorso,
                  !isRunning(execution.session)
            else { continue }
            execution.outcome = .interrotta
            automations.record(execution, for: automation.id)
        }
    }

    /// The Mac is going to sleep: every Esecuzione at work is interrupted and becomes Interrotta, waiting for Riprendi
    /// in its Sessione, and its activity is released.
    func interruptAll() {
        for automation in automations.automations {
            guard var execution = automation.lastExecution, execution.outcome == .inCorso,
                  let session = execution.session
            else { continue }
            sessions.interrupt(session)
            release(session)
            execution.outcome = .interrotta
            automations.record(execution, for: automation.id)
            Logger.automations.notice("Esecuzione interrupted by sleep")
        }
    }

    /// Ends the activity of the Esecuzione in `session`, if it holds one.
    private func release(_ session: UUID) {
        guard let activity = activities.removeValue(forKey: session) else { return }
        ProcessInfo.processInfo.endActivity(activity)
    }

    /// The prompt of an Esecuzione: the Automazione's request, and a line with its name and when it was due and
    /// started, so that the agent knows it runs alone and how to say it has nothing to report.
    static func prompt(for automation: Automation, scheduledAt: Date, startedAt: Date) -> String {
        let time = Date.FormatStyle(date: .abbreviated, time: .shortened)
        return """
            \(automation.request)

            \(String(localized: "(Esecuzione dell'Automazione «\(automation.name)», prevista \(scheduledAt.formatted(time)), partita \(startedAt.formatted(time)). Nessuno può approvare le azioni: quelle negate finiscono in un resoconto per l'utente. Se non c'è niente da fare né da segnalare, rispondi soltanto: \(nothingToReport))"))
            """
    }

    /// Whether an Esecuzione of `automation` would overlap: its own is still at work, or, outside git, where every
    /// Sessione works in the Progetto's folder, another Sessione is in a turn there.
    private func isOverlapping(_ automation: Automation) -> Bool {
        if let execution = automation.lastExecution, execution.outcome == .inCorso, isRunning(execution.session) {
            return true
        }
        guard !AutomationStore.isGitRepository(automation.project) else { return false }
        let folder = automation.project.standardizedFileURL.path
        return sessions.sessions.contains { $0.isRunning && $0.project.standardizedFileURL.path == folder }
    }

    private func isRunning(_ session: UUID?) -> Bool {
        sessions.sessions.first { $0.id == session }?.isRunning == true
    }

    /// Records how the Esecuzione in `session` ended, with its denials. Senza modifiche when its turn left no changes,
    /// no denials and ``nothingToReport`` as its last message: its Sessione is archived and its worktree gone first.
    /// Interrotta when the Mac's sleep interrupted it.
    private func finish(_ session: UUID, of id: Automation.ID, startedAt: Date, scheduledAt: Date?,
                        succeeded: Bool) async {
        release(session)
        let found = sessions.sessions.first { $0.id == session }
        let denials = found?.denials.count ?? 0
        var outcome = succeeded ? Execution.Outcome.fatta : .errore
        if found?.isInterrupted == true {
            // The Mac went to sleep while it worked: Interrotta, with its worktree kept for Riprendi.
            outcome = .interrotta
        } else if succeeded, denials == 0,
                  found?.summary?.trimmingCharacters(in: .whitespacesAndNewlines) == Self.nothingToReport,
                  let changes = try? await sessions.changes(of: session), changes.isEmpty {
            // Outside a repo the changes cannot be read: the Esecuzione stays Fatta, to be looked at.
            outcome = .senzaModifiche
            await sessions.archiveUnchanged(session)
        }
        let execution = Execution(startedAt: startedAt, scheduledAt: scheduledAt, session: session, outcome: outcome,
                                  denialCount: denials)
        automations.record(execution, for: id)
        if let automation = automations[id] { onFinish(automation, execution) }
        Logger.automations.notice("Esecuzione ended: \(outcome.rawValue, privacy: .public), denials: \(denials)")
    }
}
