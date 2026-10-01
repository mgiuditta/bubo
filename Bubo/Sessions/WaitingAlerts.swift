import Foundation

/// Tells the user which Sessioni are in Attende te: the Dock badge counts them, and each one that starts waiting
/// is announced once, unless the HUD is in front of the user. Without notifications the Dock icon bounces instead.
final class WaitingAlerts {
    /// Creates the alerts; tests replace every way to reach the user, so no real notification is ever asked for.
    ///
    /// - Parameters:
    ///   - isSeen: Whether the HUD, which shows every Sessione, is in front of the user.
    ///   - announce: Posts the notification of a Sessione, returning whether it could.
    ///   - withdraw: Removes the notification of a Sessione.
    init(isSeen: @escaping @MainActor () -> Bool, announce: @escaping @MainActor (Session) async -> Bool,
         withdraw: @escaping @MainActor (UUID) -> Void, badge: @escaping @MainActor (Int) -> Void = DockBadge.show,
         bounce: @escaping @MainActor () -> Void = DockBadge.bounce) {
        self.isSeen = isSeen
        self.announce = announce
        self.withdraw = withdraw
        self.badge = badge
        self.bounce = bounce
    }

    private let isSeen: @MainActor () -> Bool
    private let announce: @MainActor (Session) async -> Bool
    private let withdraw: @MainActor (UUID) -> Void
    private let badge: @MainActor (Int) -> Void
    private let bounce: @MainActor () -> Void
    private var waiting: Set<UUID> = []
    /// The latest announcements in flight; tests wait for them.
    private(set) var announcing: Task<Void, Never>?

    /// Follows the Attività of `sessions` after every change: alerts only for the Sessioni that just entered
    /// Attende te, and withdraws the notifications of those that left it.
    func follow(_ sessions: [Session]) {
        let waitingNow = sessions.filter { $0.phase == .aperta && $0.activity == .attende }
        let ids = Set(waitingNow.map(\.id))
        guard ids != waiting else { return }
        let started = waitingNow.filter { !waiting.contains($0.id) }
        waiting.subtracting(ids).forEach(withdraw)
        waiting = ids
        badge(ids.count)
        guard !started.isEmpty, !isSeen() else { return }
        announcing = Task {
            for session in started {
                let isPosted = await announce(session)
                // The Sessione may have left Attende te while its notification was being posted.
                if !waiting.contains(session.id) {
                    withdraw(session.id)
                } else if !isPosted {
                    bounce()
                }
            }
        }
    }
}
