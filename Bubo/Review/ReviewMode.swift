import SwiftUI

/// How the revisione shows the blocchi.
enum ReviewMode: CaseIterable, Hashable {
    /// The files on the left, the continuous diff on the right.
    case continuous
    /// One blocco at a time, large, with the row of blocchi under it.
    case focus
    /// The files on the left, before and after side by side on the right, for wide screens.
    case sideBySide

    var title: LocalizedStringKey {
        switch self {
        case .continuous: "Continuo"
        case .focus: "Focus"
        case .sideBySide: "Affiancato"
        }
    }
}
