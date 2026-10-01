import Foundation

/// How the HUD lays out the Sessioni; the user picks it in Aspetto, `UserDefaults` keeps the raw value.
// ponytail: Board arriva con la sua feature (docs/features/17-board.md).
nonisolated enum VistaDelleSessioni: String, CaseIterable, Identifiable, Sendable {
    case colonna, orbita, striscia

    /// The `UserDefaults` key of the Vista the HUD opens with.
    static let defaultsKey = "vistaDelleSessioni"

    var id: Self { self }

    /// The Vista's name in Aspetto.
    var title: LocalizedStringResource {
        switch self {
        case .colonna: "Colonna"
        case .orbita: "Orbita"
        case .striscia: "Striscia"
        }
    }
}
