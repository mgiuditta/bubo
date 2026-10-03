import Foundation

/// An area of Bubo that ships with 1.1: off in a Release build, on in a Debug build (PRD #514).
///
/// Where an area is off, its entrance shows `ComingSoonView` instead of the half-made feature.
nonisolated enum ReleaseArea: CaseIterable, Sendable {
    /// Impostazioni › Macchine and the Macchina of the Progetto (#251, #252, #253, #499).
    case machines

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
        }
    }

    /// The name of the area, as its entrance shows it.
    var title: LocalizedStringResource {
        switch self {
        case .machines: "Macchine"
        }
    }

    /// One line on what the area will do.
    var summary: LocalizedStringResource {
        switch self {
        case .machines: "Sessioni su un altro Mac o su un server via SSH, con la Macchina scelta nel Progetto."
        }
    }

    /// The SF Symbol of the area, as its entrance shows it.
    var systemImage: String {
        switch self {
        case .machines: "server.rack"
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
