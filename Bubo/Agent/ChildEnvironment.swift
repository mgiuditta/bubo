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
    ///   - claude: The user's `claude`, which the bridge starts; `nil` when there is none, and the bridge answers only
    ///     for Copilot (#719).
    ///   - apiKey: The API key, only when the user chose it (ADR 0003); never logged.
    ///   - conversations: The database where the bridge keeps its copy of the conversations; the bridge alone reads it.
    ///   - base: The environment to copy from; Bubo's own by default.
    static func make(claude: URL?, apiKey: String? = nil, conversations: URL? = nil,
                     base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base.filter { copied.contains($0.key) }
        environment["PATH"] = ([claude?.deletingLastPathComponent().path].compactMap(\.self)
                               + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"])
            .joined(separator: ":")
        environment["BUBO_CLAUDE_PATH"] = claude?.path
        environment["CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS"] = "1"
        environment["CLAUDE_AGENT_SDK_CLIENT_APP"] = "bubo/\(Bundle.main.shortVersion)"
        if let apiKey { environment["ANTHROPIC_API_KEY"] = apiKey }
        if let conversations { environment["BUBO_CONVERSATIONS"] = conversations.path }
        return environment
    }

    /// The environment of the user's `copilot`: the user's basics and a `PATH` with its own folder first, where an npm
    /// installation finds `node`.
    ///
    /// Built from scratch like the bridge's, so `COPILOT_GITHUB_TOKEN`, `GH_TOKEN` and `GITHUB_TOKEN` never reach
    /// it: `copilot` would prefer them to the login the user made with `copilot login` (ADR 0011).
    ///
    /// - Parameters:
    ///   - copilot: The user's `copilot`.
    ///   - base: The environment to copy from; Bubo's own by default.
    static func makeForCopilot(copilot: URL,
                               base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base.filter { copied.contains($0.key) }
        environment["PATH"] = [copilot.deletingLastPathComponent().path,
                               "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .joined(separator: ":")
        return environment
    }

    /// The environment of an editor's CLI: the user's basics and the system's `PATH`, where the scripts of VS Code
    /// and Cursor find `bash`.
    ///
    /// - Parameter base: The environment to copy from; Bubo's own by default.
    static func makeForEditor(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base.filter { copied.contains($0.key) }
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
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
