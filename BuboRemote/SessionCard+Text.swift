import RemoteKit
import SwiftUI

extension SessionCard.Activity {
    /// The Attività's name; keyed, since "Ferma" is also a button.
    var title: LocalizedStringResource {
        switch self {
        case .attende: LocalizedStringResource("attivita.attendeTe", defaultValue: "Attende te")
        case .lavora: LocalizedStringResource("attivita.lavora", defaultValue: "Lavora")
        case .ferma: LocalizedStringResource("attivita.ferma", defaultValue: "Ferma")
        case .errore: LocalizedStringResource("attivita.errore", defaultValue: "Errore")
        }
    }

    /// The dot's color: Lume only for Attende te, danger for Errore, faint once it stops (design system).
    var color: Color {
        switch self {
        case .attende: Color(red: 0xD6 / 255, green: 0xF2 / 255, blue: 0x6B / 255)
        case .errore: Color(red: 0xF2 / 255, green: 0x55 / 255, blue: 0x5A / 255)
        case .lavora: .primary
        case .ferma: .secondary
        }
    }
}

extension SessionCard.Phase {
    /// The Fase's name.
    var title: LocalizedStringResource {
        switch self {
        case .aperta: LocalizedStringResource("fase.aperta", defaultValue: "Aperta")
        case .inRevisione: LocalizedStringResource("fase.inRevisione", defaultValue: "In revisione")
        case .fusa: LocalizedStringResource("fase.fusa", defaultValue: "Fusa")
        case .archiviata: LocalizedStringResource("fase.archiviata", defaultValue: "Archiviata")
        }
    }
}

extension SessionCard {
    /// "Attività · Fase · N file", without the files while the diff is unknown.
    var statusLine: String {
        var parts = [String(localized: activity.title), String(localized: phase.title)]
        if let diff { parts.append(String(localized: "\(diff.files) file")) }
        return parts.joined(separator: " · ")
    }
}
