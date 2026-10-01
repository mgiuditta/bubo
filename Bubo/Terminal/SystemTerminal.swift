import AppKit

/// The Mac's own terminal, opened on a command typed for the user, who runs it with Return: Apri nel terminale from ⌘I,
/// where no Sessione has a terminal of Bubo's yet (spec 16).
///
/// No Apple Events, so no Automation permission: Bubo writes a `.command` file that the terminal app the user chose
/// for scripts opens. The file deletes itself, puts the command on zsh's line editor, ready but not run, then leaves
/// a login shell open.
struct SystemTerminal {
    /// Where the `.command` files are written.
    var folder = FileManager.default.temporaryDirectory
    /// Opens a file with its app; `NSWorkspace` outside tests.
    var open: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    /// Opens the terminal with `command` typed and not run.
    ///
    /// - Throws: `SystemTerminalError.notOpened` when no app opens the script, or the error of writing it.
    func open(typing command: String) throws {
        let file = folder.appending(path: "Bubo-\(UUID().uuidString).command")
        try Data(Self.script(typing: command).utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        guard open(file) else {
            try? FileManager.default.removeItem(at: file)
            throw SystemTerminalError.notOpened(command: command)
        }
    }

    /// The zsh script that types `command` on its line editor and runs it only on Return.
    static func script(typing command: String) -> String {
        let explanation = String(localized: "Bubo ha scritto il comando qui sotto. Premi Invio per eseguirlo, oppure chiudi la finestra.")
        return """
            #!/bin/zsh -f
            rm -f -- "$0"
            print -r -- \(quoted(explanation))
            command=\(quoted(command))
            vared -p '%# ' command && eval "$command"
            exec "${SHELL:-/bin/zsh}" -l

            """
    }

    /// `text` in single quotes, read by the shell exactly as it is.
    private static func quoted(_ text: String) -> String {
        "'" + text.replacing("'", with: #"'\''"#) + "'"
    }
}

/// Why the terminal did not open.
enum SystemTerminalError: LocalizedError {
    /// No app opened the `.command` file that types `command`.
    case notOpened(command: String)

    var errorDescription: String? {
        switch self {
        case let .notOpened(command):
            String(localized: "Il Terminale non si è aperto. Scrivi «\(command)» nel Terminale, poi riprova.")
        }
    }
}
