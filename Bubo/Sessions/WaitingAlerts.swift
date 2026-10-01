import Foundation

/// Tells the user which Sessioni are in Attende te: the Dock badge counts them, and each one that starts waiting
/// is announced once, unless the HUD is in front of the user. Without notifications the Dock icon bounces instead.
///
/// The notification carries the oldest Richiesta di permesso of the Sessione, if any: when another one takes its place
/// the notification is posted again for it, and when none is left it is withdrawn, so it never answers a stale one.
final class WaitingAlerts {
    /// Creates the alerts; tests replace every way to reach the user, so no real notification is ever asked for.
    ///
    /// - Parameters:
    ///   - isSeen: Whether the HUD, which shows every Sessione, is in front of the user.
    ///   - announce: Posts the notification of a Sessione with its oldest Richiesta, returning whether it could.
    ///   - withdraw: Removes the notification of a Sessione.
    init(isSeen: @escaping @MainActor () -> Bool,
         announce: @escaping @MainActor (Session, RequestCenter.Pending?) async -> Bool,
         withdraw: @escaping @MainActor (UUID) -> Void, badge: @escaping @MainActor (Int) -> Void = DockBadge.show,
         bounce: @escaping @MainActor () -> Void = DockBadge.bounce) {
        self.isSeen = isSeen
        self.announce = announce
        self.withdraw = withdraw
        self.badge = badge
        self.bounce = bounce
    }

    private let isSeen: @MainActor () -> Bool
    private let announce: @MainActor (Session, RequestCenter.Pending?) async -> Bool
    private let withdraw: @MainActor (UUID) -> Void
    private let badge: @MainActor (Int) -> Void
    private let bounce: @MainActor () -> Void
    /// The Sessioni in Attende te, with the Richiesta their notification is about.
    private var waiting: [UUID: PermissionRequest.ID?] = [:]
    /// The latest announcements in flight, after the earlier ones; tests wait for them.
    private(set) var announcing: Task<Void, Never>?

    /// Follows the Attività of `sessions` and their `requests` after every change: alerts only for the Sessioni that
    /// just entered Attende te or whose oldest Richiesta changed, and withdraws the notifications that are stale.
    func follow(_ sessions: [Session], requests: RequestCenter = RequestCenter()) {
        var now: [UUID: PermissionRequest.ID?] = [:]
        var started: [(Session, RequestCenter.Pending?)] = []
        for session in sessions where session.phase == .aperta && session.activity == .attende {
            let pending = requests.queues[session.id]?.first
            now[session.id] = .some(pending?.id)
            switch waiting[session.id] {
            case .none:
                started.append((session, pending))
            case let .some(previous) where previous != pending?.id:
                // Its notification may answer only the Richiesta it shows.
                withdraw(session.id)
                if pending != nil { started.append((session, pending)) }
            default:
                break
            }
        }
        guard now != waiting else { return }
        waiting.keys.filter { now[$0] == nil }.forEach(withdraw)
        if Set(now.keys) != Set(waiting.keys) { badge(now.count) }
        waiting = now
        guard !started.isEmpty, !isSeen() else { return }
        announcing = Task { [previous = announcing] in
            // One after the other: a late post never removes a newer one.
            await previous?.value
            for (session, pending) in started {
                let isPosted = await announce(session, pending)
                // The Sessione may have left Attende te, or moved to another Richiesta, while it was being posted.
                if waiting[session.id] != .some(pending?.id) {
                    withdraw(session.id)
                } else if !isPosted {
                    bounce()
                }
            }
        }
    }
}
