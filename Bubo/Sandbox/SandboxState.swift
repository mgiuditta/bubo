import Foundation

/// What the Sandbox indicator of a Sessione says: never "spenta" while commands still run in the Sandbox, nor the
/// other way round.
nonisolated enum SandboxState: Equatable, Sendable {
    case on, off
    /// The turn in progress runs outside the Sandbox; the next one runs in it.
    case onFromNextTurn
    /// The turn in progress runs in the Sandbox; the next one runs outside it.
    case offFromNextTurn

    /// The state when the Progetto has the Sandbox on or off, and the turn in progress, if any, runs in it or not.
    init(isEnabled: Bool, currentTurn isCurrentTurnSandboxed: Bool?) {
        switch (isEnabled, isCurrentTurnSandboxed ?? isEnabled) {
        case (true, true): self = .on
        case (false, false): self = .off
        case (true, false): self = .onFromNextTurn
        case (false, true): self = .offFromNextTurn
        }
    }

    /// Whether the commands running now, or the next ones when none runs, are in the Sandbox.
    var isSandboxedNow: Bool { self == .on || self == .offFromNextTurn }

    /// The indicator's text.
    var title: LocalizedStringResource {
        switch self {
        case .on: "Sandbox accesa"
        case .off: "Sandbox spenta"
        case .onFromNextTurn: "Sandbox accesa dal prossimo turno"
        case .offFromNextTurn: "Sandbox spenta dal prossimo turno"
        }
    }
}
