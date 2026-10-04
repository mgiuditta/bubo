import Foundation
import XCTest

/// A home folder of its own for one onboarding (spec 26): a `claude` that answers at once, and one recent Progetto.
///
/// Bubo finds `claude` and the recent Progetti from its home, and keeps the Sessioni in its Application Support, so a
/// new home is a first launch: the user's own Sessioni and `~/.claude.json` stay untouched. With `isLive` the `claude`
/// is the user's, linked from its usual place; children keep the real `HOME`, where its login is.
nonisolated struct FakeClaudeHome {
    /// The home folder Bubo sees.
    let folder: URL
    /// The Progetto offered as the only recent one: a plain folder, so the Sessione needs no worktree.
    let project: URL
    /// Whether the `claude` is the user's real one.
    let isLive: Bool

    /// Where the fake `claude` writes the arguments of each run, one line per run.
    private var invocationLog: URL { folder.appending(path: "claude-invocations.log") }

    /// Creates a new home in `/tmp`: the runner's own temporary folder is in its container, which macOS hides from the
    /// `claude` that Bubo starts disclaimed.
    ///
    /// - Parameter isLive: Whether to link the user's `claude` instead of the fake one, `claude-finto.zsh`.
    /// - Throws: When a file cannot be written, or with `isLive` when no `claude` is installed.
    init(isLive: Bool = false) throws {
        self.isLive = isLive
        folder = URL(filePath: "/private/tmp/bubo-onboarding-\(UUID().uuidString)", directoryHint: .isDirectory)
        project = folder.appending(path: "progetto-onboarding", directoryHint: .isDirectory)
        let files = FileManager.default
        let bin = folder.appending(path: ".local/bin", directoryHint: .isDirectory)
        try files.createDirectory(at: bin, withIntermediateDirectories: true)
        try files.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("# Progetto di prova\n".utf8).write(to: project.appending(path: "README.md"))
        // Only the keys of `projects` count for the recent Progetti.
        let claudeJSON = try JSONSerialization.data(withJSONObject: ["projects": [project.path: [String: String]()]])
        try claudeJSON.write(to: folder.appending(path: ".claude.json"))

        let claude = bin.appending(path: "claude")
        if isLive {
            let installed = try Self.installedClaude()
            try files.createSymbolicLink(at: claude, withDestinationURL: installed)
        } else {
            // A link to the script in the test bundle: a file written by the sandboxed runner is quarantined, and
            // macOS would not run it.
            let fake = try XCTUnwrap(Bundle(for: OnboardingPerfTests.self).url(forResource: "claude-finto", withExtension: "zsh"))
            try files.createSymbolicLink(at: claude, withDestinationURL: fake)
        }
    }

    /// The variables that make Bubo, the bridge and the fake `claude` live in this home.
    ///
    /// `CFFIXED_USER_HOME` moves Foundation's home and Application Support; `UserDefaults` stays the user's.
    var environment: [String: String] {
        var environment = ["CFFIXED_USER_HOME": folder.path]
        if !isLive { environment["HOME"] = folder.path }
        return environment
    }

    /// The runs of the fake `claude` so far, each as its time, its parent process and its arguments.
    var invocations: [String] {
        guard let log = try? String(contentsOf: invocationLog, encoding: .utf8) else { return [] }
        return log.split(separator: "\n").map(String.init)
    }

    /// Deletes the home and everything Bubo wrote in it.
    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The user's `claude`, from the places `ClaudeLocator` tries first.
    private static func installedClaude() throws -> URL {
        let candidates = [URL.homeDirectory.appending(path: ".local/bin/claude"), URL(filePath: "/opt/homebrew/bin/claude"),
                          URL(filePath: "/usr/local/bin/claude")]
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return found
    }
}
