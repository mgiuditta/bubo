import Foundation

/// The environment of the agent bridge and of the `claude` it starts, built from scratch.
///
/// Nothing of Bubo's own environment leaks through: no `ANTHROPIC_*`, no `CLAUDE_CODE_SANDBOXED`.
/// The subscription login is read by `claude` from the Keychain, so it needs only `HOME` and `USER`.
nonisolated enum ChildEnvironment {
    /// The variables copied from Bubo's environment when present.
    static let copied = ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG"]

    /// The environment for the bridge.
    ///
    /// - Parameters:
    ///   - claude: The user's `claude`, which the bridge starts.
    ///   - apiKey: The API key, only when the user chose it (ADR 0003); never logged.
    ///   - conversations: The database where the bridge keeps its copy of the conversations; the bridge alone reads it.
    ///   - base: The environment to copy from; Bubo's own by default.
    static func make(claude: URL, apiKey: String? = nil, conversations: URL? = nil,
                     base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base.filter { copied.contains($0.key) }
        environment["PATH"] = [claude.deletingLastPathComponent().path,
                               "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .joined(separator: ":")
        environment["BUBO_CLAUDE_PATH"] = claude.path
        environment["CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS"] = "1"
        environment["CLAUDE_AGENT_SDK_CLIENT_APP"] = "bubo/\(Bundle.main.shortVersion)"
        if let apiKey { environment["ANTHROPIC_API_KEY"] = apiKey }
        if let conversations { environment["BUBO_CONVERSATIONS"] = conversations.path }
        return environment
    }

    /// The environment of a Sessione's terminal: the user's basics, the Sessione's ports, and a terminal that
    /// understands colours. The login shell adds the user's `PATH` from the profile.
    ///
    /// - Parameters:
    ///   - session: The Sessione whose `PORT`, `BUBO_PORT` and `BUBO_PORTS` the shell gets.
    ///   - base: The environment to copy from; Bubo's own by default.
    static func makeForTerminal(of session: Session,
                                base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base.filter { copied.contains($0.key) }
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Bubo"
        if environment["LANG"] == nil { environment["LC_CTYPE"] = "UTF-8" }
        return environment.merging(session.portEnvironment) { $1 }
    }
}

private extension Bundle {
    nonisolated var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
}
