import Foundation

/// The Livello di rischio of an action, from 1 to 5; no Regola di permesso ever comes from levels 4–5.
nonisolated enum RiskLevel: Int, Comparable, CaseIterable, Sendable {
    case lettura = 1, modifica, rete, distruttivo, irreversibile

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The level's name in the HUD.
    var title: LocalizedStringResource {
        switch self {
        case .lettura: "Lettura"
        case .modifica: "Modifica reversibile"
        case .rete: "Rete"
        case .distruttivo: "Distruttivo locale"
        case .irreversibile: "Irreversibile esterno"
        }
    }

    /// Whether approving takes a 1-second press instead of one key, and no "always" is offered.
    var isDangerous: Bool { self >= .distruttivo }
}

/// How risky a call is: its level, and whether it touches a path `claude` itself never lets anyone approve.
nonisolated struct Risk: Equatable, Sendable {
    var level: RiskLevel
    /// Whether the call removes a critical path of `claude` (the root, a top-level folder, the home folder, the
    /// working folder or a parent of it, an unresolved variable): never approvable.
    var isCritical = false

    /// A critical removal.
    static let critical = Risk(level: .irreversibile, isCritical: true)

    /// The higher of the two risks.
    func merged(with other: Risk) -> Risk {
        Risk(level: max(level, other.level), isCritical: isCritical || other.isCritical)
    }
}
