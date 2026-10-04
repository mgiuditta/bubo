import Foundation

/// An area of Bubo that ships with 1.1: off in a Release build, on in a Debug build (PRD #514).
///
/// Where an area is off, its entrance shows `ComingSoonView` instead of the half-made feature.
nonisolated enum ReleaseArea: CaseIterable, Sendable {
    /// Impostazioni › Macchine and the Macchina of the Progetto (#251, #252, #253, #499).
    case machines
    /// Impostazioni › iPhone and the Telecomando's sync with the iPhone (#244, #245).
    case remote
    /// Impostazioni › Consegne, the foglio di Consegna and the `.bubo` files opened in Bubo (#274, #495).
    case deliveries
    /// The Sandbox of the Progetto, its indicator in the HUD and its proposal with the Modalità autonoma (#214).
    case sandbox
    /// The Neuroni, the graph of the notes of the Secondo cervello (#658).
    case neurons

    /// The areas a Release build offers. Turning an area on for a release is adding it here, and nothing else.
    static let released: Set<ReleaseArea> = []

    /// The defaults key of the Debug switch that turns the unreleased areas off, as a Release build has them.
    static let hidesUnreleasedKey = "debugHidesUnreleasedAreas"

    /// Whether this build is a Debug build.
    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// The 1.1 issue the area waits for, on `mgiuditta/bubo`.
    var issue: Int {
        switch self {
        case .machines: 251
        case .remote: 245
        case .deliveries: 274
        case .sandbox: 214
        case .neurons: 658
        }
    }

    /// The name of the area, as its entrance shows it.
    var title: LocalizedStringResource {
        switch self {
        case .machines: "Macchine"
        case .remote: "Telecomando"
        case .deliveries: "Consegne"
        case .sandbox: "Sandbox"
        case .neurons: "Neuroni"
        }
    }

    /// One line on what the area will do.
    var summary: LocalizedStringResource {
        switch self {
        case .machines: "Sessioni su un altro Mac o su un server via SSH, con la Macchina scelta nel Progetto."
        case .remote: "Rispondi alle Sessioni e alle Richieste di permesso dall'iPhone, anche lontano dal Mac."
        case .deliveries: "Passa una Sessione a un'altra persona che usa Bubo, in un file .bubo cifrato."
        case .sandbox: "I comandi di Claude scrivono solo nella cartella della Sessione e raggiungono solo gli host consentiti."
        case .neurons: "Le note del Secondo cervello come una rete dei loro collegamenti, con le note citate nell'ultima risposta."
        }
    }

    /// The SF Symbol of the area, as its entrance shows it.
    var systemImage: String {
        switch self {
        case .machines: "server.rack"
        case .remote: "iphone"
        case .deliveries: "shippingbox"
        case .sandbox: "lock.shield"
        case .neurons: "point.3.connected.trianglepath.dotted"
        }
    }

    /// Returns whether the area is available in a build.
    ///
    /// - Parameters:
    ///   - isDebugBuild: Whether the build is a Debug build, where every area is on unless hidden.
    ///   - hidesUnreleased: Whether the Debug switch turns the unreleased areas off; a Release build ignores it.
    func isAvailable(
        isDebugBuild: Bool = Self.isDebugBuild,
        hidesUnreleased: Bool = UserDefaults.standard.bool(forKey: Self.hidesUnreleasedKey)
    ) -> Bool {
        Self.released.contains(self) || (isDebugBuild && !hidesUnreleased)
    }
}
