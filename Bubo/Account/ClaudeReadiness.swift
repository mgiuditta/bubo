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
    /// `claude` is older than `minimumVersion`.
    case outdated(version: String)

    /// The oldest `claude` Bubo runs.
    // ponytail: placeholder until spec 27 puts the minimum in bridge/compat.json (#188).
    static let minimumVersion = [2, 1, 0]

    /// Finds `claude` with `locator` and asks it for its version and login.
    ///
    /// - Parameter runner: Runs `claude`; by default disclaimed, with the environment the bridge gets.
    static func detect(
        locator: ClaudeLocator = ClaudeLocator(),
        runner: ProcessRunner = ProcessRunner { claude, arguments in
            try await ProcessRunner.disclaimed(environment: ChildEnvironment.make(claude: claude)).run(claude, arguments)
        }
    ) async -> ClaudeReadiness {
        guard let claude = await locator.executableURL(),
              let output = try? await runner.run(claude, ["--version"]), output.exitCode == 0,
              let version = output.standardOutput.split(whereSeparator: \.isWhitespace).first.map(String.init)
        else { return .missing }
        let numbers = version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard !numbers.lexicographicallyPrecedes(minimumVersion) else { return .outdated(version: version) }
        guard let output = try? await runner.run(claude, ["auth", "status", "--json"]), output.exitCode == 0,
              let status = try? JSONDecoder().decode(AuthStatus.self, from: Data(output.standardOutput.utf8)),
              status.loggedIn
        else { return .signedOut(version: version) }
        let method = status.authMethod?.hasPrefix("api") == true
            ? "API key"
            : status.subscriptionType?.capitalized ?? status.authMethod ?? ""
        return .ready(version: version, method: method)
    }
}
