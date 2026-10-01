import Foundation

/// How the HUD lays out the Sessioni; the user picks it in Aspetto, `UserDefaults` keeps the raw value.
// ponytail: Board arriva con la sua feature (docs/features/17-board.md).
nonisolated enum VistaDelleSessioni: String, CaseIterable, Identifiable, Sendable {
    case colonna, orbita, striscia

    /// The `UserDefaults` key of the Vista the HUD opens with.
    static let defaultsKey = "vistaDelleSessioni"

    var id: Self { self }

    /// The Vista chosen in Aspetto and kept in `defaults`; Colonna until one is chosen.
    static func chosen(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .colonna
    }

    /// The key that, with ⌘, shows the Vista in the HUD.
    var shortcut: Character {
        switch self {
        case .colonna: "1"
        case .orbita: "2"
        case .striscia: "3"
        }
    }

    /// The Vista's name in Aspetto.
    var title: LocalizedStringResource {
        switch self {
        case .colonna: "Colonna"
        case .orbita: "Orbita"
        case .striscia: "Striscia"
        }
    }
}
