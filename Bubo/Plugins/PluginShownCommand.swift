/// The command a `command` source runs on the Mac, as the CLI showed it, with its fingerprint for `--accept-command`.
nonisolated struct PluginShownCommand: Sendable, Equatable {
    /// The shell command, exactly as the CLI would run it.
    let command: String
    /// The fingerprint `--accept-command` accepts: only this command, for this plugin and this catalog.
    let sha256: String
}
