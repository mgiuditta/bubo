import Foundation

/// A Richiesta di permesso of a Sessione, as the iPhone shows it and decides it (spec 21).
///
/// Travels only inside the encrypted payload of a ``RemoteRecord`` of kind `request`; only its ``category`` goes in
/// clear, to pick the notification's actions.
public struct RemoteRequest: Codable, Sendable, Equatable, Identifiable {
    /// How long the iPhone may decide a Richiesta after the Mac sends it: 10 minutes, as long as a Verdict lives.
    public static let decisionWindow: TimeInterval = VerdictVerifier.maximumAge

    /// The notification category of a Request record: which answers the notification offers.
    public enum Category: String, Codable, Sendable, CaseIterable {
        /// Levels 1–3: Consenti per questa Sessione, Consenti solo ora, No.
        case requestLow = "REQUEST_LOW"
        /// Levels 1–3 where the Mac offers no permission for the Sessione: Consenti solo ora, No.
        case requestLowOnce = "REQUEST_LOW_ONCE"
        /// Levels 4–5, or a call `claude` says one key must not approve: only Apri per decidere.
        case requestHigh = "REQUEST_HIGH"
        /// Resolved on the Mac: the notification is rewritten without actions.
        case resolved = "RESOLVED"

        /// The answers the notification's actions give; none where the user must open the app, or nothing waits.
        public var notificationAnswers: [Verdict.Answer] {
            switch self {
            case .requestLow: [.allowForSession, .allowOnce, .deny]
            case .requestLowOnce: [.allowOnce, .deny]
            case .requestHigh, .resolved: []
            }
        }
    }

    /// The random identifier the Verdict answers; not the identifier `claude` gave the Richiesta.
    public let id: UUID
    /// The Sessione that asks.
    public let sessionID: UUID
    /// The Sessione's title.
    public var sessionTitle: String
    /// The Progetto's name: its folder's name, never its path.
    public var project: String
    /// The Livello di rischio, from 1 to 5.
    public var level: Int
    /// The tool, such as `Bash` or `Edit`.
    public var tool: String
    /// The command, file, address or host the call works on, whole.
    public var subject: String?
    /// Why `claude` asks, in its words.
    public var reason: String?
    /// Whether Consenti per questa Sessione is offered.
    public var allowsSessionRule: Bool
    /// Whether the decision takes the full-screen page: levels 4–5, or `claude` says one key must not approve it.
    public var needsReview: Bool
    /// Until when the iPhone may decide it; later, only the Mac.
    public let expiresAt: Date
    /// Whether the Mac resolved it: the record stays only to rewrite the notification.
    public var isResolved: Bool

    /// Creates a Richiesta as the iPhone sees it.
    public init(id: UUID = UUID(), sessionID: UUID, sessionTitle: String, project: String, level: Int, tool: String,
                subject: String?, reason: String?, allowsSessionRule: Bool, needsReview: Bool, expiresAt: Date,
                isResolved: Bool = false) {
        self.id = id
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.project = project
        self.level = level
        self.tool = tool
        self.subject = subject
        self.reason = reason
        self.allowsSessionRule = allowsSessionRule
        self.needsReview = needsReview
        self.expiresAt = expiresAt
        self.isResolved = isResolved
    }

    /// The notification category, from the Richiesta and never from the Livello alone.
    public var category: Category {
        if isResolved { .resolved } else if needsReview { .requestHigh } else if allowsSessionRule { .requestLow } else {
            .requestLowOnce
        }
    }

    /// The answers the iPhone may give, in the app as in the notification: on the full-screen page only No and
    /// Consenti solo ora. "Sempre in questo Progetto" exists only on the Mac.
    public var answers: [Verdict.Answer] {
        if isResolved { [] } else if allowsSessionRule && !needsReview { [.deny, .allowOnce, .allowForSession] } else {
            [.deny, .allowOnce]
        }
    }

    /// Whether the iPhone may still decide it at `date`.
    public func isExpired(at date: Date) -> Bool {
        date > expiresAt
    }
}
