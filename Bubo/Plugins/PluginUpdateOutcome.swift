import Foundation

/// How Aggiorna ended.
nonisolated enum PluginUpdateOutcome: Sendable, Equatable {
    /// The new version is installed.
    case updated
    /// `claude` left the installed version as it was: the author did not change the version.
    case unchanged
    /// The source is a command `claude` runs only once the person has read it, with its fingerprint.
    case needsConfirmation(PluginShownCommand)
    /// `claude` refused, with its message.
    case failed(PluginCommandResult)
}

nonisolated extension PluginUpdateOutcome {
    /// What the detail says when `claude` left the version as it was.
    static let unchangedMessage: LocalizedStringResource = "L'autore non ha cambiato versione: questa è già l'ultima che pubblica."
}
