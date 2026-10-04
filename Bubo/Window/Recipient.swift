import Foundation

/// Who the composer writes to: the Cervello (a Domanda) or a Progetto (a Sessione) (ADR 0013).
enum Recipient: Hashable {
    case brain
    case project(URL)

    /// The name on the chip.
    var name: String {
        switch self {
        case .brain: String(localized: "Cervello")
        case .project(let folder): folder.lastPathComponent
        }
    }

    /// What VoiceOver reads for the chip.
    var accessibilityLabel: String {
        String(localized: "Destinatario: \(name)")
    }
}
