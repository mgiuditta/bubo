import os
import UserNotifications

/// Posts the native notifications of the Sessioni in Attende te: one per Sessione, in its own thread.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Creates a notifier that calls `openHUD` when the user clicks a notification.
    init(openHUD: @escaping @MainActor () -> Void) {
        self.openHUD = openHUD
    }

    private let openHUD: @MainActor () -> Void
    private let center = UNUserNotificationCenter.current()

    /// Receives the clicks, also the one that launches Bubo, and removes the notifications of the previous launch:
    /// none of its Sessioni waits any more.
    func start() {
        center.delegate = self
        center.removeAllDeliveredNotifications()
    }

    /// Announces that `session` waits for the user, asking for the permission the first time.
    ///
    /// - Returns: Whether the notification was posted; `false` when the user denied notifications.
    func announce(_ session: Session) async -> Bool {
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { return false }
            let content = UNMutableNotificationContent()
            content.title = session.title
            content.subtitle = String(localized: Session.Activity.attende.title)
            content.body = session.summary ?? ""
            content.threadIdentifier = session.id.uuidString
            content.sound = .default
            try await center.add(UNNotificationRequest(identifier: session.id.uuidString, content: content, trigger: nil))
            return true
        } catch {
            Logger.sessions.error("Notification not posted: \(error)")
            return false
        }
    }

    /// Removes the notification of the Sessione `id`, which no longer waits.
    func withdraw(_ id: UUID) {
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    /// Shows the banner also with Bubo in front: a Sessione in front of the user is never announced.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await openHUD()
    }
}
