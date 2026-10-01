import Foundation

/// Finds the user's `claude`, never on Bubo's own `PATH`: an app opened from the Finder
/// has only `/usr/bin:/bin:/usr/sbin:/sbin` (spec 26).
///
/// The `claude` found is the one `ClaudeCLI` runs and the bridge passes as `pathToClaudeCodeExecutable`.
nonisolated struct ClaudeLocator: Sendable {
    /// The user's home folder.
    var home = URL.homeDirectory
    /// Whether a file is an executable; the only file system access, and never to credentials.
    var isExecutable: @Sendable (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    /// Runs the login shell, disclaimed so its profile asks for Files and Folders in its own name (ADR 0005).
    var runner = ProcessRunner.disclaimed(
        environment: ProcessInfo.processInfo.environment.filter { ChildEnvironment.copied.contains($0.key) }
    )
    /// The user's login shell.
    var shell = URL(filePath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
    /// How long the login shell may take: a profile can stall on a prompt.
    var shellTimeout = Duration.seconds(5)

    /// Where the installers put `claude`, in the order they are tried: native, Homebrew,
    /// `/usr/local`, npm's global folder, legacy.
    var candidates: [URL] {
        [
            home.appending(path: ".local/bin/claude"),
            URL(filePath: "/opt/homebrew/bin/claude"),
            URL(filePath: "/usr/local/bin/claude"),
            home.appending(path: ".npm-global/bin/claude"),
            home.appending(path: ".claude/local/claude"),
        ]
    }

    /// Every `claude` installed among the candidates, first the one Bubo uses.
    ///
    /// Only when there is none, asks an interactive login shell, as Terminal would.
    func installations() async -> [URL] {
        let found = candidates.filter(isExecutable)
        guard found.isEmpty else { return found }
        return await claudeOnLoginPath().map { [$0] } ?? []
    }

    /// The `claude` Bubo uses, or `nil` when there is none.
    func executableURL() async -> URL? {
        await installations().first
    }

    private func claudeOnLoginPath() async -> URL? {
        let output = try? await withThrowingTaskGroup { group in
            group.addTask { try await runner.run(shell, ["-l", "-i", "-c", "command -v claude"]) }
            group.addTask {
                try await Task.sleep(for: shellTimeout)
                throw CancellationError()
            }
            defer { group.cancelAll() }
            return try await group.next()
        }
        guard let output, output.exitCode == 0,
              let path = output.standardOutput.split(whereSeparator: \.isNewline).last,
              path.hasPrefix("/")
        else { return nil }
        return URL(filePath: String(path))
    }
}
