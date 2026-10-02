import Foundation
import os

/// Runs the Automazioni: each Esecuzione, by its Ripetizione or by [Avvia ora], is a new Sessione in a new worktree,
/// marked "Automazione", whose turn runs with nobody in front of it (spec 19).
final class ExecutionRunner {
    init(automations: AutomationStore, sessions: SessionStore) {
        self.automations = automations
        self.sessions = sessions
    }

    /// The last message the prompt asks for when there is nothing to do: with no changes and no denials, it makes the
    /// Esecuzione Senza modifiche.
    static let nothingToReport = String(localized: "Niente da segnalare.")

    private let automations: AutomationStore
    private let sessions: SessionStore

    /// Starts an Esecuzione of the Automazione `id` now, and records it in its history; or records it Saltata
    /// (sovrapposta) while the same Automazione is still at work, or, outside git, another Sessione works in its
    /// Progetto's folder.
    ///
    /// - Parameters:
    ///   - scheduledAt: When its Ripetizione had it due; `nil` for [Avvia ora].
    /// - Returns: The id of the Esecuzione's Sessione; `nil` when it did not start or the Automazione is gone.
    @discardableResult
    func run(_ id: Automation.ID, scheduledAt: Date? = nil, at date: Date = .now) -> UUID? {
        guard let automation = automations[id] else { return nil }
        if isOverlapping(automation) {
            automations.record(Execution(startedAt: date, scheduledAt: scheduledAt, outcome: .saltata,
                                         skipReason: .sovrapposta), for: id)
            Logger.automations.notice("Esecuzione skipped: overlapping")
            return nil
        }
        let mark = AutomationMark(automation: id, name: automation.name, startedAt: date)
        let turn = UnattendedTurn(rules: automation.rules, model: automation.model.alias)
        let prompt = Self.prompt(for: automation, scheduledAt: scheduledAt ?? date, startedAt: date)
        let session = sessions.startExecution(prompt, title: automation.name,
                                              branch: Session.proposedBranch(for: "automazione \(automation.name)"),
                                              in: automation.project, automation: mark, unattended: turn,
                                              isAutonomous: automation.isAutonomous) { [weak self] session, succeeded in
            await self?.finish(session, of: id, startedAt: date, scheduledAt: scheduledAt, succeeded: succeeded)
        }
        automations.record(Execution(startedAt: date, scheduledAt: scheduledAt, session: session, outcome: .inCorso),
                           for: id)
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
    private func finish(_ session: UUID, of id: Automation.ID, startedAt: Date, scheduledAt: Date?,
                        succeeded: Bool) async {
        let found = sessions.sessions.first { $0.id == session }
        let denials = found?.denials.count ?? 0
        var outcome = succeeded ? Execution.Outcome.fatta : .errore
        // Outside git the changes cannot be read: the Esecuzione stays Fatta, to be looked at.
        if succeeded, denials == 0,
           found?.summary?.trimmingCharacters(in: .whitespacesAndNewlines) == Self.nothingToReport,
           let changes = try? await sessions.changes(of: session), changes.isEmpty {
            outcome = .senzaModifiche
            await sessions.archiveUnchanged(session)
        }
        automations.record(Execution(startedAt: startedAt, scheduledAt: scheduledAt, session: session, outcome: outcome,
                                     denialCount: denials), for: id)
        Logger.automations.notice("Esecuzione ended: \(outcome.rawValue, privacy: .public), denials: \(denials)")
    }
}
