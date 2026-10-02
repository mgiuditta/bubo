import RemoteKit
import UserNotifications

/// The notifications of the Richieste (spec 21): their categories and actions, and the answers given from them.
///
/// An action of levels 1–3 asks to unlock the iPhone with Face ID, then signs the Verdict in the background with the
/// same Face ID; Apri per decidere opens the Richiesta full screen in Attende te.
final class RemoteNotifications: NSObject, UNUserNotificationCenterDelegate {
    private let model: RemoteModel
    private let center = UNUserNotificationCenter.current()

    /// Creates the notifications that answer through `model`.
    init(model: RemoteModel) {
        self.model = model
    }

    /// Receives the actions, also the one that launches the app, and declares the categories.
    func start() {
        center.delegate = self
        center.setNotificationCategories(Set(RemoteRequest.Category.allCases.map(Self.category)))
    }

    /// Asks once for alerts, sounds and the badge; the Richieste need them to reach the user away from the Mac.
    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Removes the delivered notifications of the Richieste that no longer wait, those not in `waiting`.
    static func withdrawAll(except waiting: Set<UUID>) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.deliveredNotifications().filter { notification in
            RequestNotification.target(in: notification.request.content.userInfo)
                .map { !waiting.contains($0.requestID) } ?? false
        }
        center.removeDeliveredNotifications(withIdentifiers: stale.map(\.request.identifier))
    }

    /// The category `category`, with an action for each answer it offers from the notification.
    private static func category(_ category: RemoteRequest.Category) -> UNNotificationCategory {
        let actions: [UNNotificationAction] = switch category {
        case .requestHigh:
            [UNNotificationAction(identifier: RequestNotification.openAction,
                                  title: String(localized: "Apri per decidere"), options: .foreground)]
        case .requestLow, .requestLowOnce, .resolved:
            category.notificationAnswers.map { answer in
                UNNotificationAction(identifier: RequestNotification.actionIdentifier(for: answer),
                                     title: String(localized: answer.notificationTitle),
                                     options: answer == .deny ? [.authenticationRequired, .destructive]
                                         : .authenticationRequired)
            }
        }
        return UNNotificationCategory(identifier: category.rawValue, actions: actions, intentIdentifiers: [])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Signs the answer of the action in the background; any other tap opens the Richiesta in the app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard let target = RequestNotification.target(in: content.userInfo) else { return }
        let answer = RequestNotification.answer(forAction: response.actionIdentifier)
        await handle(answer, to: target.requestID, of: target.macID, expiresAt: target.expiresAt,
                     title: content.title)
    }

    private func handle(_ answer: Verdict.Answer?, to requestID: UUID, of macID: UUID, expiresAt: Date,
                        title: String) async {
        guard let answer else {
            model.focusedRequest = requestID
            return
        }
        do {
            try await model.answer(requestID, of: macID, with: answer, expiresAt: expiresAt)
        } catch {
            // The action ran in the background: the reason goes in a notification that opens the Richiesta.
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = String(localized: error.message)
            content.userInfo = [RequestNotification.requestIDKey: requestID.uuidString,
                                RequestNotification.macIDKey: macID.uuidString,
                                RequestNotification.expiresAtKey: expiresAt.timeIntervalSince1970]
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

extension Verdict.Answer {
    /// The title of the notification's action that gives this answer.
    var notificationTitle: LocalizedStringResource {
        switch self {
        case .deny: "No"
        case .allowOnce: "Consenti solo ora"
        case .allowForSession: "Consenti per questa Sessione"
        }
    }
}
