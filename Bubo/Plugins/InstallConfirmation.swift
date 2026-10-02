/// What the Installa sheet knows about the command of a `command` source, and the install command it allows.
///
/// The fingerprint goes to `--accept-command` only once the person ticked the box under that very command: never
/// before, never `-y` (spec 20, criterion 7).
nonisolated struct InstallConfirmation: Sendable, Equatable {
    /// The command the CLI showed and refused to run without confirmation.
    private(set) var shownCommand: PluginShownCommand?
    /// Whether the box "Ho letto il comando e mi fido" is ticked.
    var isAccepted = false

    /// Whether Installa can run: always, except with a command shown and the box not ticked.
    var allowsInstall: Bool { shownCommand == nil || isAccepted }

    /// The install command of `plugin` in `scope`.
    func installCommand(for plugin: PluginID, scope: PluginScope) -> PluginCommand {
        .install(plugin, scope: scope, accepting: isAccepted ? shownCommand : nil)
    }

    /// Takes in what the CLI answered: a command shown, or shown again because it changed, needs a new tick.
    ///
    /// - Returns: Whether the person must now read a command and tick the box.
    mutating func update(with result: PluginCommandResult) -> Bool {
        guard result.needsCommandConfirmation, let shown = result.shownCommand else { return false }
        if shown != shownCommand || !isAccepted {
            shownCommand = shown
            isAccepted = false
            return true
        }
        return false
    }
}
