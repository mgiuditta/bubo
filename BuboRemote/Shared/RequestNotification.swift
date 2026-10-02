import Foundation
import RemoteKit

/// What the notification of a Richiesta carries between the extension that writes it and the app that answers it.
nonisolated enum RequestNotification {
    /// The `userInfo` key of the Richiesta's identifier.
    static let requestIDKey = "requestID"
    /// The `userInfo` key of the Mac's identifier.
    static let macIDKey = "macID"
    /// The `userInfo` key of the end of the decision window, in seconds since 1970.
    static let expiresAtKey = "expiresAt"
    /// The action that opens the app on the Richiesta.
    static let openAction = "OPEN"

    /// The identifier of the action that gives `answer`.
    static func actionIdentifier(for answer: Verdict.Answer) -> String {
        "ANSWER_" + answer.rawValue
    }

    /// The answer of the action `identifier`; `nil` for any other action.
    static func answer(forAction identifier: String) -> Verdict.Answer? {
        Verdict.Answer.allCases.first { actionIdentifier(for: $0) == identifier }
    }

    /// The `userInfo` of the notification of `request`, from the Mac `macID`.
    static func userInfo(of request: RemoteRequest, macID: UUID) -> [String: Any] {
        [requestIDKey: request.id.uuidString, macIDKey: macID.uuidString,
         expiresAtKey: request.expiresAt.timeIntervalSince1970]
    }

    /// The Richiesta, Mac and end of decision window in `userInfo`; `nil` when it is not a Richiesta's.
    static func target(in userInfo: [AnyHashable: Any]) -> (requestID: UUID, macID: UUID, expiresAt: Date)? {
        guard let request = (userInfo[requestIDKey] as? String).flatMap(UUID.init(uuidString:)),
              let mac = (userInfo[macIDKey] as? String).flatMap(UUID.init(uuidString:)),
              let expiresAt = userInfo[expiresAtKey] as? TimeInterval
        else { return nil }
        return (request, mac, Date(timeIntervalSince1970: expiresAt))
    }
}
