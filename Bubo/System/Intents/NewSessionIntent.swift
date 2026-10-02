import AppIntents
import Foundation

/// Where "Nuova Sessione" starts its Sessione: the Sessioni of the HUD, set at launch.
protocol SessionStarting: AnyObject {
    /// The known Progetti, those with Sessioni, most recent first.
    var projects: [URL] { get }
    /// Returns whether `claude` may load the settings of `project` (#266).
    func isTrusted(_ project: URL) -> Bool
    /// Starts a Sessione that does `request` on the trusted `project`.
    func startSession(_ request: String, in project: URL) throws
    /// Brings the HUD to the front with the new Sessione sheet filled in, where Crea asks for trust in `project`.
    func askTrust(toStart request: String, in project: URL)
    /// Shows `message` in the Panel: why the Sessione did not start.
    func report(_ message: String)
}

/// "Nuova Sessione", from Spotlight and Comandi rapidi (spec 09): a Progetto and a text become a Sessione at once,
/// without opening the HUD.
///
/// On a Progetto not trusted yet the HUD comes to the front with the new Sessione, which asks for trust: without an
/// answer no Sessione starts. On a Progetto that is gone nothing starts, and the Panel says why.
struct NewSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Nuova Sessione"
    static let description = IntentDescription("Avvia una Sessione di Claude su un Progetto. Bubo lavora senza aprire l'HUD.")
    /// Bubo works in the background: the HUD opens only to ask for trust.
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Progetto")
    var project: ProjectEntity

    @Parameter(title: "Cosa deve fare Claude?", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Nuova Sessione su \(\.$project): \(\.$text)")
    }

    /// Where the Sessioni start, set at launch before any intent runs; tests set a stand-in.
    @MainActor static var starter: (any SessionStarting)?

    /// The known Progetti, for the parameter; none before launch set `starter`.
    @MainActor static func knownProjects() -> [URL] {
        starter?.projects ?? []
    }

    func perform() async throws -> some IntentResult {
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            throw $text.needsValueError("Che cosa deve fare Claude?")
        }
        try await Self.start(request, in: project.folder)
        return .result()
    }

    /// Starts `request` on `project` through `starter`, or asks for trust first.
    ///
    /// - Throws: `NewSessionError.notReady` before launch set `starter`; `NewSessionError.projectMissing` when the
    ///   folder is gone, with nothing started.
    @MainActor private static func start(_ request: String, in project: URL) throws {
        guard let starter else { throw NewSessionError.notReady }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            let error = NewSessionError.projectMissing(project.lastPathComponent)
            starter.report(String(localized: error.localizedStringResource))
            throw error
        }
        if starter.isTrusted(project) {
            try starter.startSession(request, in: project)
        } else {
            starter.askTrust(toStart: request, in: project)
        }
    }
}

/// Why "Nuova Sessione" did not start its Sessione.
enum NewSessionError: Error, Equatable, CustomLocalizedStringResourceConvertible {
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
