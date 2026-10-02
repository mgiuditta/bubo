import Foundation

/// Whether the user's `claude` can answer, from `claude --version` and `claude auth status` (spec 26).
///
/// `ready` says only that a credential exists: whether it works shows at the first request.
/// Bubo never reads the credentials of `claude` to find out (ADR 0003).
nonisolated enum ClaudeReadiness: Equatable, Sendable {
    /// `claude` is installed and signed in; `method` is the plan, such as `Max`, or `API key`.
    case ready(version: String, method: String)
    /// No `claude`, or one that does not run.
    case missing
    /// `claude` has no credential.
    case signedOut(version: String)
    /// `claude` is older than the minimum of `ClaudeCompatibility`, or than the one Anthropic requires; `version` is
    /// empty when `claude` did not say it.
    case outdated(version: String)

    /// The `claude` that runs by default: disclaimed, with the environment the bridge gets.
    static let defaultRunner = ProcessRunner { claude, arguments in
        try await ProcessRunner.disclaimed(environment: ChildEnvironment.make(claude: claude)).run(claude, arguments)
    }

    /// Finds `claude` with `locator` and asks it for its version and login.
    ///
    /// - Parameters:
    ///   - runner: Runs `claude`.
    ///   - compatibility: The minimum version.
    static func detect(locator: ClaudeLocator = ClaudeLocator(), runner: ProcessRunner = defaultRunner,
                       compatibility: ClaudeCompatibility = .bundled) async -> ClaudeReadiness {
        guard let (claude, version) = await version(locator: locator, runner: runner) else { return .missing }
        guard !compatibility.isOutdated(version) else { return .outdated(version: version) }
        guard let output = try? await runner.run(claude, ["auth", "status", "--json"]), output.exitCode == 0,
              let status = try? JSONDecoder().decode(AuthStatus.self, from: Data(output.standardOutput.utf8)),
              status.loggedIn
        else { return .signedOut(version: version) }
        let method = status.authMethod?.hasPrefix("api") == true
            ? "API key"
            : status.subscriptionType?.capitalized ?? status.authMethod ?? ""
        return .ready(version: version, method: method)
    }

    /// The version of `claude` when it is too old to start a Sessione, from `claude --version` alone: checked before
    /// the prompt leaves.
    ///
    /// Returns `nil` for a `claude` at or above the minimum, and for a missing one: then the bridge says so.
    static func outdatedVersion(locator: ClaudeLocator = ClaudeLocator(), runner: ProcessRunner = defaultRunner,
                                compatibility: ClaudeCompatibility = .bundled) async -> String? {
        guard let (_, version) = await version(locator: locator, runner: runner), compatibility.isOutdated(version)
        else { return nil }
        return version
    }

    /// The version of the `claude` that `locator` finds, such as `2.1.287`; `nil` when it is missing or fails.
    static func installedVersion(locator: ClaudeLocator = ClaudeLocator(), runner: ProcessRunner = defaultRunner) async
        -> String? {
        await version(locator: locator, runner: runner)?.version
    }

    /// The `claude` that `locator` finds, with the first word of its `--version`; `nil` when it is missing or fails.
    private static func version(locator: ClaudeLocator, runner: ProcessRunner) async -> (claude: URL, version: String)? {
        guard let claude = await locator.executableURL(),
              let output = try? await runner.run(claude, ["--version"]), output.exitCode == 0,
              let version = output.standardOutput.split(whereSeparator: \.isWhitespace).first.map(String.init)
        else { return nil }
        return (claude, version)
    }
}
