import CloudKit
import CryptoKit
import Foundation
import RemoteKit
import UserNotifications

/// Writes the notification of a Richiesta from its encrypted record (spec 21): title "Progetto · Sessione",
/// subtitle "Livello N · scade tra 10 min", body with the reason and the command, cut.
///
/// CloudKit carries only clear metadata; the text exists only here, after the decryption with the pair's key. When the
/// record does not open, the notification says only that a Sessione waits, without actions.
nonisolated final class NotificationService: UNNotificationServiceExtension {
    /// The longest command in the body; the full-screen page shows it whole.
    static let subjectLimit = 120

    /// Writes the content of the notification from the record, on the extension's thread. Nothing waits on the
    /// network: the record travels in the push, and the key is in the keychain.
    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            return contentHandler(request.content)
        }
        Self.write(Self.open(request.content.userInfo), into: content)
        contentHandler(content)
    }

    /// The Richiesta in the CloudKit notification `userInfo`, with its Mac; `nil` when it does not open.
    ///
    /// The subscription asks for the record's `payload`, `macID` and `deviceID` in the push (`desiredKeys`).
    private static func open(_ userInfo: [AnyHashable: Any]) -> (request: RemoteRequest, macID: UUID)? {
        guard let notification = CKQueryNotification(fromRemoteNotificationDictionary: userInfo),
              let recordID = notification.recordID?.recordName,
              let fields = notification.recordFields,
              let macID = (fields["macID"] as? String).flatMap(UUID.init(uuidString:)),
              let payload = fields["payload"] as? Data,
              let mac = try? KeychainStore<PairedMac>(service: PairedMac.keychainService).itemsBlocking()
                  .first(where: { $0.id == macID }),
              let request = try? RecordSealer(key: SymmetricKey(data: mac.recordKey))
                  .open(RemoteRequest.self, from: payload, recordID: recordID)
        else { return nil }
        return (request, macID)
    }

    private static func write(_ opened: (request: RemoteRequest, macID: UUID)?, into content: UNMutableNotificationContent) {
        guard let (request, macID) = opened else {
            content.title = String(localized: "Bubo: una Sessione aspetta una decisione")
            content.subtitle = ""
            content.body = ""
            content.categoryIdentifier = ""
            return
        }
        content.title = "\(request.project) · \(request.sessionTitle)"
        content.threadIdentifier = request.sessionID.uuidString
        content.userInfo.merge(RequestNotification.userInfo(of: request, macID: macID)) { _, new in new }
        if request.isResolved {
            content.subtitle = ""
            content.body = String(localized: "Già risolta sul Mac")
            content.categoryIdentifier = RemoteRequest.Category.resolved.rawValue
            content.interruptionLevel = .passive
            return
        }
        let minutes = Duration.seconds(max(60, request.expiresAt.timeIntervalSinceNow))
            .formatted(.units(allowed: [.minutes], width: .abbreviated))
        content.subtitle = String(localized: "Livello \(request.level) · scade tra \(minutes)")
        let reason = request.reason ?? request.tool
        let subject = request.subject.map { $0.count > subjectLimit ? String($0.prefix(subjectLimit)) + "…" : $0 }
        content.body = [reason, subject].compactMap(\.self).joined(separator: "\n")
        content.categoryIdentifier = request.category.rawValue
        content.interruptionLevel = .timeSensitive
    }
}
