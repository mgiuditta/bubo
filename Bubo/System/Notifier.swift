import os
import UserNotifications

/// Posts the native notifications of the Sessioni in Attende te: one per Sessione, in its own thread.
///
/// The notification of a Richiesta di permesso answers it without bringing Bubo to the front: No always, Solo ora
/// only where `PermissionNotice` offers it. Each answer carries the ids of its Sessione and Richiesta, so it reaches
/// that Richiesta only, and nothing if it no longer waits.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Creates a notifier that calls `openHUD` when the user clicks a notification, with the Sessione it is about if
    /// any, and `answer` with the Richiesta, its Sessione and whether the call may run when the user picks Solo ora or
    /// No.
    init(openHUD: @escaping @MainActor (UUID?) -> Void,
         answer: @escaping @MainActor (PermissionRequest.ID, UUID, Bool) -> Void) {
        self.openHUD = openHUD
        self.answer = answer
    }

    private let openHUD: @MainActor (UUID?) -> Void
    private let answer: @MainActor (PermissionRequest.ID, UUID, Bool) -> Void
    private let center = UNUserNotificationCenter.current()

    /// The notifications' categories and actions, and the keys of the ids they carry.
    private nonisolated enum Identifier {
        static let request = "richiesta"
        static let requestToOpen = "richiesta-da-aprire"
        static let allowOnce = "solo-ora"
        static let deny = "no"
        static let open = "apri"
        static let session = "sessione"
    }

    /// Receives the clicks, also the one that launches Bubo, and removes the notifications of the previous launch:
    /// none of its Sessioni waits any more.
    func start() {
        center.delegate = self
        center.removeAllDeliveredNotifications()
        // Only Apri Bubo brings Bubo to the front; dismissing a notification answers nothing.
        let deny = UNNotificationAction(identifier: Identifier.deny, title: String(localized: "No"))
        let allowOnce = UNNotificationAction(identifier: Identifier.allowOnce, title: String(localized: "Solo ora"),
                                             options: .authenticationRequired)
        let open = UNNotificationAction(identifier: Identifier.open, title: String(localized: "Apri Bubo"),
                                        options: .foreground)
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Identifier.request, actions: [deny, allowOnce], intentIdentifiers: []),
            UNNotificationCategory(identifier: Identifier.requestToOpen, actions: [deny, open], intentIdentifiers: []),
        ])
    }

    /// Announces that `session` waits for the user, for `pending` if it is a Richiesta di permesso.
    ///
    /// The permission is provisional: no system alert, the notifications go quietly to the Notification Center until
    /// the user chooses to keep them (spec 26).
    ///
    /// - Returns: Whether the notification was posted; `false` when the user turned notifications off.
    func announce(_ session: Session, request pending: RequestCenter.Pending?) async -> Bool {
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound, .provisional]) else { return false }
            let content = UNMutableNotificationContent()
            content.title = session.title
            if let pending {
                let notice = PermissionNotice(pending)
                content.subtitle = notice.subtitle
                content.body = notice.body
                content.categoryIdentifier = notice.offersAllowOnce ? Identifier.request : Identifier.requestToOpen
                content.userInfo = [Identifier.session: session.id.uuidString, Identifier.request: pending.id]
            } else {
                content.subtitle = String(localized: Session.Activity.attende.title)
                content.body = session.summary ?? ""
            }
            content.threadIdentifier = session.id.uuidString
            content.sound = .default
            try await center.add(UNNotificationRequest(identifier: session.id.uuidString, content: content, trigger: nil))
            return true
        } catch {
            Logger.sessions.error("Notification not posted: \(error)")
            return false
        }
    }

    /// Announces that the recovery started an Esecuzione of `automation` for the time it missed, `scheduledAt`.
    func announceRecovery(of automation: Automation, scheduledAt: Date) async {
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound, .provisional]) else { return }
            let content = UNMutableNotificationContent()
            content.title = automation.name
            content.body = String(localized: "Recupero dell'Esecuzione prevista \(scheduledAt.formatted(date: .abbreviated, time: .shortened)): era persa mentre il Mac dormiva o Bubo era chiuso.")
            content.threadIdentifier = automation.id.uuidString
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        } catch {
            Logger.automations.error("Recovery notification not posted: \(error)")
        }
    }

    /// Announces how `execution` of `automation` ended, with its outcome and how many actions were denied: nothing
    /// for one with nothing to look at. A click opens the HUD on its Sessione.
    func announceResult(of execution: Execution, from automation: Automation) async {
        guard let notice = execution.resultNotice, let session = execution.session else { return }
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound, .provisional]) else { return }
            let content = UNMutableNotificationContent()
            content.title = automation.name
            content.subtitle = String(localized: "Automazione · \(execution.startedAt.formatted(date: .omitted, time: .shortened))")
            content.body = notice
            content.threadIdentifier = automation.id.uuidString
            content.userInfo = [Identifier.session: session.uuidString]
            content.sound = .default
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        } catch {
            Logger.automations.error("Result notification not posted: \(error)")
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

    /// Answers the Richiesta of the notification with Solo ora or No, in the background; any other click opens the HUD,
    /// on the Sessione of the notification if it has one.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let ids = response.notification.request.content.userInfo
        let allows: Bool? = switch response.actionIdentifier {
        case Identifier.allowOnce: true
        case Identifier.deny: false
        default: nil
        }
        let session = (ids[Identifier.session] as? String).flatMap(UUID.init(uuidString:))
        guard let allows, let request = ids[Identifier.request] as? String, let session else {
            await openHUD(session)
            return
        }
        await answer(request, session, allows)
    }
}
