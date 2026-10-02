import Foundation
import os

/// Logs in to an MCP server that waits for OAuth, with `claude mcp login` (spec 20, `needs-auth`).
///
/// `claude` opens the browser and ends once the login is done; after 5 minutes it is stopped. Not in the queue of the
/// plugin commands: the wait for the browser would hold every other command up, and the login writes only the
/// server's credentials, which `claude` keeps in the Keychain.
nonisolated struct MCPLogin: Sendable {
    /// Runs `claude` with the arguments in the folder and returns its output.
    var run: @Sendable (_ arguments: [String], _ folder: URL) async throws -> ProcessOutput
    /// How long the login may take.
    var timeout = Duration.seconds(300)

    /// The user's `claude`, found by `locator`, with the environment of the plugin commands.
    static func live(locator: ClaudeLocator = ClaudeLocator(),
                     environment: [String: String] = PluginListing.environment()) -> MCPLogin {
        MCPLogin { arguments, folder in
            guard let claude = await locator.executableURL() else { throw PluginCLIError.claudeMissing }
            return try await ProcessRunner.disclaimed(environment: environment, in: folder, mergingErrors: true)
                .run(claude, arguments)
        }
    }

    /// Logs in to `server` with `claude` started in `folder`, where it finds the servers of the Progetto.
    ///
    /// - Returns: Whether `claude` ended with success; `false` also when it is missing or took too long.
    /// - Throws: `CancellationError` when the task is cancelled.
    func logIn(to server: String, in folder: URL) async throws -> Bool {
        let run = run
        let timeout = timeout
        do {
            let output = try await withThrowingTaskGroup { group in
                group.addTask { try await run(["mcp", "login", "--", server], folder) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw PluginCLIError.timedOut
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            // Never the output in the log: it may carry the authorization URL.
            Logger.plugins.notice("claude mcp login ended with \(output.exitCode)")
            return output.exitCode == 0
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Logger.plugins.notice("claude mcp login failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// The command to type in the Terminale when the login from Bubo fails, in `project` when the server is one of it.
    static func commandLine(for server: String, in project: URL?) -> String {
        let login = "claude mcp login \(shellQuoted(server))"
        return project.map { "cd \(shellQuoted($0.path)) && \(login)" } ?? login
    }

    /// `text` as one word for the shell: as it is when it is safe, in single quotes otherwise.
    private static func shellQuoted(_ text: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:@"))
        guard !text.isEmpty, text.unicodeScalars.allSatisfy(safe.contains), !text.hasPrefix("-") else {
            return "'" + text.replacing("'", with: #"'\''"#) + "'"
        }
        return text
    }
}
