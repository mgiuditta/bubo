import Foundation

/// A server of `.claude/launch.json`, the format of Claude desktop that Bubo reads instead of having its own
/// (spec 15). The server gets the Sessione's `PORT`, unless it must keep its own `port` (`autoPort: false`).
nonisolated struct LaunchConfig: Decodable, Equatable, Sendable {
    let name: String
    var runtimeExecutable: String?
    var runtimeArgs: [String]?
    /// A script run with `node`, with `args`, when there is no `runtimeExecutable`.
    var program: String?
    var args: [String]?
    /// The folder to run in, relative to the Sessione's; `${workspaceFolder}` is the Sessione's.
    var cwd: String?
    var env: [String: String]?
    /// The port the server listens on; with `autoPort: false` it keeps it, as for an OAuth callback.
    var port: Int?
    var autoPort: Bool?

    private struct File: Decodable {
        let configurations: [LaunchConfig]
    }

    /// The servers of `.claude/launch.json` in `folder` that have a command; none when it is missing or unreadable.
    static func read(in folder: URL) -> [LaunchConfig] {
        let decoder = JSONDecoder()
        // "The file supports JSON with comments."
        decoder.allowsJSON5 = true
        guard let data = try? Data(contentsOf: folder.appending(path: ".claude/launch.json")),
              let file = try? decoder.decode(File.self, from: data)
        else { return [] }
        return file.configurations.filter { $0.commandLine != nil }
    }

    /// The command as the shell reads it, each word quoted when needed; `nil` for a server Bubo cannot start.
    var commandLine: String? {
        let words: [String]
        if let runtimeExecutable, !runtimeExecutable.isEmpty {
            words = [runtimeExecutable] + (runtimeArgs ?? [])
        } else if let program, !program.isEmpty {
            words = ["node", program] + (args ?? [])
        } else {
            return nil
        }
        return words.map(Self.quoted).joined(separator: " ")
    }

    /// The variables the server starts with: its `env`, then the Sessione's `ports`, then its own `port` when it
    /// cannot take another.
    func environment(over ports: [String: String]) -> [String: String] {
        var environment = (env ?? [:]).merging(ports) { $1 }
        if autoPort == false, let port { environment["PORT"] = String(port) }
        return environment
    }

    /// The folder to run in, inside `folder`, the Sessione's.
    func folder(in folder: URL) -> URL {
        guard let cwd, !cwd.isEmpty else { return folder }
        let relative = cwd.replacing("${workspaceFolder}", with: "")
            .trimmingPrefix { $0 == "/" }
        return relative.isEmpty ? folder : folder.appending(path: String(relative), directoryHint: .isDirectory)
    }

    /// `word` as one word for a POSIX shell.
    private static func quoted(_ word: String) -> String {
        let plain = word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_./=:@%+,".contains($0)) }
        return plain && !word.isEmpty ? word : "'" + word.replacing("'", with: #"'\''"#) + "'"
    }
}
