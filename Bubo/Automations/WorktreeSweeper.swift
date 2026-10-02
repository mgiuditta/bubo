import Foundation
import os

/// Removes, in the background, the worktrees that the Archiviate Sessioni of the Esecuzioni still have after a crash
/// cut their archive short: no orphan worktree stays after a week (spec 19).
final class WorktreeSweeper {
    /// How often the sweep runs, besides at launch.
    static let interval: TimeInterval = 6 * 60 * 60

    private let automations: AutomationStore
    private let sessions: SessionStore
    private var activity: NSBackgroundActivityScheduler?

    /// Creates a sweeper for the Sessioni of the Esecuzioni of `automations`.
    init(automations: AutomationStore, sessions: SessionStore) {
        self.automations = automations
        self.sessions = sessions
    }

    isolated deinit {
        activity?.invalidate()
    }

    /// Sweeps now, then every ``interval`` when the system sees fit.
    func start() {
        Task { await sweep() }
        let activity = NSBackgroundActivityScheduler(identifier: "com.mgiuditta.bubo.worktree-sweeper")
        activity.repeats = true
        activity.interval = Self.interval
        activity.qualityOfService = .utility
        activity.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.sweep()
                completion(.finished)
            }
        }
        self.activity = activity
    }

    /// Removes the worktrees left to the Archiviate Sessioni of the Esecuzioni; the branch goes too for those Senza
    /// modifiche, as their archive would have done.
    ///
    /// - Returns: How many worktrees were removed.
    @discardableResult
    func sweep() async -> Int {
        let executions = automations.automations.flatMap(\.executions).filter { $0.session != nil }
        var removed = 0
        for execution in executions {
            guard let session = execution.session else { continue }
            if await sessions.removeLeftoverWorktree(of: session, deletingBranch: execution.outcome == .senzaModifiche) {
                removed += 1
            }
        }
        if removed > 0 { Logger.automations.notice("Orphan worktrees removed: \(removed)") }
        return removed
    }
}
