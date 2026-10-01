import Darwin
import Foundation

/// The Sandbox of a Sessione's turn, as `Options.sandbox` (spec 22): the fixed preset and the denied credentials.
///
/// One object for all of it: the SDK puts `Options.sandbox` in place of the whole `sandbox` of `Options.settings`,
/// so nothing of the Sandbox goes anywhere else. Bash and its children run in Seatbelt: they write only in the
/// Sessione's folder, the temporary folder and the package caches, reach only the package registries, and cannot
/// read `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.netrc` or the variables that hold tokens.
nonisolated struct SandboxPolicy: Equatable, Sendable {
    /// The package registries that sandboxed commands reach without asking. Never `github.com`: the proxy reads only
    /// the host name, so a domain that wide lets anything out.
    static let allowedDomains = ["registry.npmjs.org", "pypi.org", "files.pythonhosted.org", "crates.io",
                                 "index.crates.io", "static.crates.io", "rubygems.org", "index.rubygems.org"]

    /// The folders sandboxed commands also write in, beyond the Sessione's own.
    let writablePaths: [String]
    /// The credential files and folders sandboxed commands cannot read.
    let deniedFiles: [String]
    /// The environment variables sandboxed commands do not get.
    let deniedVariables: [String]

    /// Creates the Sandbox for a `claude` started with `environment`.
    ///
    /// - Parameters:
    ///   - environment: The environment `claude` gets; its variables that look like tokens are denied, by name.
    ///   - userTemporaryFolder: `DARWIN_USER_TEMP_DIR`, writable.
    ///   - userCacheFolder: `DARWIN_USER_CACHE_DIR`, writable.
    init(environment: [String: String], userTemporaryFolder: String? = Self.darwinFolder(_CS_DARWIN_USER_TEMP_DIR),
         userCacheFolder: String? = Self.darwinFolder(_CS_DARWIN_USER_CACHE_DIR)) {
        let home = environment["HOME"] ?? NSHomeDirectory()
        writablePaths = [userTemporaryFolder, userCacheFolder].compactMap(\.self)
            + [".npm", ".cargo/registry", "Library/Caches/pip"].map { "\(home)/\($0)" }
        deniedFiles = [".ssh", ".aws", ".gnupg", ".netrc"].map { "\(home)/\($0)" }
        deniedVariables = environment.keys.filter(Self.holdsSecret).sorted()
    }

    /// Whether the variable `name` looks like it holds a token, a key or a password.
    static func holdsSecret(_ name: String) -> Bool {
        name.hasPrefix("AWS_") || ["_TOKEN", "_API_KEY", "_SECRET", "_PASSWORD"].contains { name.hasSuffix($0) }
    }

    /// The Sandbox as the JSON object of `Options.sandbox`.
    ///
    /// Sandboxed commands run without asking: the bridge's gate still asks for levels 4–5 and for every command that
    /// wants out of the Sandbox. Until Bubo shows "Rete: host" Richieste (spec 22, step 3), a host outside
    /// `allowedDomains` is denied at once.
    var jsonObject: [String: Any] {
        [
            "enabled": true,
            "failIfUnavailable": true,
            "autoAllowBashIfSandboxed": true,
            "allowUnsandboxedCommands": true,
            "network": ["allowedDomains": Self.allowedDomains, "allowLocalBinding": true, "strictAllowlist": true],
            "filesystem": ["allowWrite": writablePaths],
            "credentials": [
                "files": deniedFiles.map { ["path": $0, "mode": "deny"] },
                "envVars": deniedVariables.map { ["name": $0, "mode": "deny"] },
            ],
        ]
    }

    /// A per-user folder of Darwin, without its trailing slash; `nil` when the system does not tell it.
    static func darwinFolder(_ name: Int32) -> String? {
        let length = confstr(name, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(name, &buffer, length) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
