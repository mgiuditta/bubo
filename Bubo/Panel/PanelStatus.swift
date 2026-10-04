import Foundation

/// What the pill beside the reduced Orb says: something that waits for the user, never a plain state.
///
/// Sessioni in Attende te come first, then those in Errore, then the Domanda that ended with the bubble closed.
nonisolated enum PanelStatus: Equatable, Sendable {
    /// `count` Sessioni are in Attende te; a click shows `session`, the first of them.
    case waiting(count: Int, session: Session.ID)
    /// `count` Sessioni are in Errore; a click shows `session`, the first of them.
    case failing(count: Int, session: Session.ID)
    /// The Domanda's answer ended while the bubble was closed.
    case answerReady
    /// The Domanda failed while the bubble was closed.
    case questionFailed
    /// Media files or a web link are dragged over the Orb: a drop transcribes them into the Secondo cervello.
    case dropHint

    /// Returns what the pill says for `sessions` and the Domanda, or `nil` when there is nothing to say.
    ///
    /// - Parameters:
    ///   - sessions: The Sessioni; only the live ones count.
    ///   - hasUnseenOutcome: Whether the Domanda ended with the bubble closed and nobody has looked since.
    ///   - questionFailed: Whether that Domanda ended in a failure.
    static func status(sessions: [Session], hasUnseenOutcome: Bool, questionFailed: Bool) -> PanelStatus? {
        let live = sessions.filter(\.isLive)
        let waiting = live.filter { $0.activity == .attende }
        if let first = waiting.first { return .waiting(count: waiting.count, session: first.id) }
        let failing = live.filter { $0.activity == .errore }
        if let first = failing.first { return .failing(count: failing.count, session: first.id) }
        guard hasUnseenOutcome else { return nil }
        return questionFailed ? .questionFailed : .answerReady
    }

    /// The short text on the pill.
    var text: String {
        switch self {
        case .waiting(let count, _): String(localized: "\(count) ti attendono")
        case .failing(let count, _): String(localized: "\(count) in Errore")
        case .answerReady: String(localized: "Risposta pronta")
        case .questionFailed: String(localized: "Domanda non riuscita")
        case .dropHint: String(localized: "Rilascia per farne una Riunione")
        }
    }

    /// The full name VoiceOver reads for the pill.
    var accessibilityLabel: String {
        switch self {
        case .waiting(let count, _): Self.waitingDescription(count: count)
        case .failing(let count, _): Self.failingDescription(count: count)
        case .answerReady, .questionFailed, .dropHint: text
        }
    }

    /// What a click on the pill does, for VoiceOver and the tooltip.
    var help: String {
        switch self {
        case .waiting, .failing: String(localized: "Apre la Sessione nell'HUD")
        case .answerReady, .questionFailed: String(localized: "Riapre la Domanda nel Panel")
        case .dropHint: String(localized: "Bubo trascrive l'audio e salva la Riunione nel Secondo cervello")
        }
    }

    /// Whether the pill carries the Lume dot: only for Attende te, as the menu bar's owl.
    var showsLume: Bool {
        if case .waiting = self { true } else { false }
    }

    /// Returns what the Orb's VoiceOver value adds about `sessions`: those in Attende te and those in Errore, or
    /// `nil` when none is.
    static func sessionsDescription(of sessions: [Session]) -> String? {
        let live = sessions.filter(\.isLive)
        let waiting = live.count { $0.activity == .attende }
        let failing = live.count { $0.activity == .errore }
        let parts = [
            waiting > 0 ? waitingDescription(count: waiting) : nil,
            failing > 0 ? failingDescription(count: failing) : nil,
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func waitingDescription(count: Int) -> String {
        String(localized: "\(count) Sessioni ti attendono")
    }

    private static func failingDescription(count: Int) -> String {
        String(localized: "\(count) Sessioni in Errore")
    }
}
