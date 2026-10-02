import AppIntents
import Foundation

/// Where "Apri Galassia" opens its window: the Galassia windows, set at launch.
protocol GalaxyOpening: AnyObject {
    /// Shows the Galassia of `project`, bringing forward its window when it has one.
    func show(_ project: URL)
}

extension GalaxyStore: GalaxyOpening {}

/// "Apri Galassia", from Spotlight, Comandi rapidi and the voice (spec 11): opens the Galassia of a Progetto, or brings
/// its window forward when it is already open. It asks for no permission.
struct OpenGalaxyIntent: OpenIntent {
    static let title: LocalizedStringResource = "Apri Galassia"
    static let description = IntentDescription("Apre la Galassia di un Progetto: la mappa dei suoi file con le Sessioni al lavoro.")

    @Parameter(title: "Progetto")
    var target: ProjectEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Apri la Galassia di \(\.$target)")
    }

    /// Where the Galassia opens, set at launch before any intent runs; tests set a stand-in.
    @MainActor static var galaxies: (any GalaxyOpening)?

    func perform() async throws -> some IntentResult {
        try await Self.open(target.folder)
        return .result()
    }

    /// Opens the Galassia of `project` through `galaxies`.
    ///
    /// - Throws: `OpenGalaxyError.notReady` before launch set `galaxies`; `OpenGalaxyError.projectMissing` when the
    ///   folder is gone, with nothing opened.
    @MainActor private static func open(_ project: URL) throws {
        guard let galaxies else { throw OpenGalaxyError.notReady }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw OpenGalaxyError.projectMissing(project.lastPathComponent) }
        galaxies.show(project)
    }
}

/// Why "Apri Galassia" did not open the Galassia.
enum OpenGalaxyError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    /// The Progetto's folder, named here, is no longer there.
    case projectMissing(String)
    /// Bubo is still starting.
    case notReady

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .projectMissing(name): "Il Progetto «\(name)» non c'è più: è stato spostato o cancellato. Scegline un altro."
        case .notReady: "Bubo si sta avviando. Riprova tra un attimo."
        }
    }
}
