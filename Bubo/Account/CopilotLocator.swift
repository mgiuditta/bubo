import Foundation

/// Finds the user's `copilot` (GitHub Copilot CLI), never on Bubo's own `PATH`: an app opened from the Finder has only
/// `/usr/bin:/bin:/usr/sbin:/sbin` (ADR 0011, like `ClaudeLocator`).
nonisolated struct CopilotLocator: Sendable {
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

    /// Where the installers put `copilot`, in the order they are tried: Homebrew (`brew install copilot-cli`),
    /// `/usr/local`, the install script, npm's global folder.
    var candidates: [URL] {
        [
            URL(filePath: "/opt/homebrew/bin/copilot"),
            URL(filePath: "/usr/local/bin/copilot"),
            home.appending(path: ".local/bin/copilot"),
            home.appending(path: ".npm-global/bin/copilot"),
        ]
    }

    /// The `copilot` Bubo uses, or `nil` when there is none.
    ///
    /// Only when no candidate is there, asks an interactive login shell, as Terminal would.
    func executableURL() async -> URL? {
        if let found = candidates.first(where: isExecutable) { return found }
        guard let output = await runner.run(shell, ["-l", "-i", "-c", "command -v copilot"], timeout: shellTimeout),
              output.exitCode == 0,
              let path = output.standardOutput.split(whereSeparator: \.isNewline).last,
              path.hasPrefix("/")
        else { return nil }
        return URL(filePath: String(path))
    }
}
