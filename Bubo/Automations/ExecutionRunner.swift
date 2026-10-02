import Foundation
import os

/// Runs the Automazioni: [Avvia ora] starts an Esecuzione, a new Sessione in a new worktree, marked "Automazione",
/// whose turn runs with nobody in front of it (spec 19).
final class ExecutionRunner {
    init(automations: AutomationStore, sessions: SessionStore) {
        self.automations = automations
        self.sessions = sessions
    }

    private let automations: AutomationStore
    private let sessions: SessionStore

    /// [Avvia ora]: starts an Esecuzione of the Automazione `id` now, and records it as its latest.
    ///
    /// - Returns: The id of the Esecuzione's Sessione; `nil` when the Automazione is gone.
    @discardableResult
    func run(_ id: Automation.ID, at date: Date = .now) -> UUID? {
        guard let automation = automations[id] else { return nil }
        let mark = AutomationMark(automation: id, name: automation.name, startedAt: date)
        let turn = UnattendedTurn(rules: automation.rules, model: automation.model.alias)
        let session = sessions.startExecution(Self.prompt(for: automation, scheduledAt: date, startedAt: date),
                                              title: automation.name,
                                              branch: Session.proposedBranch(for: "automazione \(automation.name)"),
                                              in: automation.project, automation: mark, unattended: turn,
                                              isAutonomous: automation.isAutonomous) { [weak self] session, succeeded in
            self?.finish(session, of: id, startedAt: date, succeeded: succeeded)
        }
        automations.record(Execution(startedAt: date, session: session, outcome: .inCorso, denialCount: 0), for: id)
        Logger.automations.notice("Esecuzione started")
        return session
    }

    /// The prompt of an Esecuzione: the Automazione's request, and a line with its name and when it was due and
    /// started, so that the agent knows it runs alone.
    static func prompt(for automation: Automation, scheduledAt: Date, startedAt: Date) -> String {
        let time = Date.FormatStyle(date: .abbreviated, time: .shortened)
        return """
            \(automation.request)

            \(String(localized: "(Esecuzione dell'Automazione «\(automation.name)», prevista \(scheduledAt.formatted(time)), partita \(startedAt.formatted(time)). Nessuno può approvare le azioni: quelle negate finiscono in un resoconto per l'utente.)"))
            """
    }

    /// Records how the Esecuzione in `session` ended, with its denials, unless a newer one replaced it.
    private func finish(_ session: UUID, of id: Automation.ID, startedAt: Date, succeeded: Bool) {
        guard automations[id]?.lastExecution?.session == session else { return }
        let denials = sessions.sessions.first { $0.id == session }?.denials.count ?? 0
        automations.record(Execution(startedAt: startedAt, session: session, outcome: succeeded ? .fatta : .errore,
                                     denialCount: denials), for: id)
        Logger.automations.notice("Esecuzione ended, succeeded: \(succeeded), denials: \(denials)")
    }
}
