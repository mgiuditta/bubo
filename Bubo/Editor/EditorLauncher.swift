import AppKit
import os

/// Finds the installed editors and opens a file in one at the line, with the disclaim of ADR 0005 (spec 15).
///
/// Never through `vscode://`: VS Code asks for confirmation before opening a file from a URL.
enum EditorLauncher {
    /// The `UserDefaults` key of the editor chosen in the Impostazioni; empty for the first one found.
    static let defaultsKey = "editorBundleID"

    /// Where the app `bundleID` is installed, from Launch Services; `nil` when it is not.
    nonisolated static func application(of bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// The known editors that are installed, in the order of ``Editor/known``.
    nonisolated static func installed(locate: (String) -> URL? = application(of:)) -> [Editor] {
        Editor.known.compactMap { known in
            locate(known.bundleID).map { Editor(bundleID: known.bundleID, application: $0) }
        }
    }

    /// The editor files open in: the one `chosen` while it is installed, else the first known one found; `nil`
    /// when there is none, and "Apri nell'editor" does not show.
    nonisolated static func preferred(chosen: String, locate: (String) -> URL? = application(of:)) -> Editor? {
        if !chosen.isEmpty, let application = locate(chosen) {
            return Editor(bundleID: chosen, application: application)
        }
        return installed(locate: locate).first
    }

    /// Opens `location` in `editor`, with `folder` as the window's folder, through the editor's CLI started
    /// disclaimed: neither the CLI nor the editor it may start has Bubo as the responsible process.
    static func open(_ location: SourceLocation, in folder: URL?, with editor: Editor) {
        let command = editor.command(opening: location, in: folder)
        let runner = ProcessRunner.disclaimed(environment: ChildEnvironment.makeForEditor())
        let name = editor.name
        Task {
            do {
                let output = try await runner.run(command.executable, command.arguments)
                if output.exitCode != 0 {
                    Logger.editor.error("\(name, privacy: .public) exited with \(output.exitCode) opening a file")
                }
            } catch {
                Logger.editor.error("\(name, privacy: .public) not started: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

extension Logger {
    nonisolated static let editor = Logger(subsystem: "com.mgiuditta.bubo", category: "editor")
}
