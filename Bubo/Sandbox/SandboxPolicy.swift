import Darwin
import Foundation

/// The Sandbox of a Sessione's turn, as `Options.sandbox` (spec 22): the fixed preset and the denied credentials.
///
/// One object for all of it: the SDK puts `Options.sandbox` in place of the whole `sandbox` of `Options.settings`,
/// so nothing of the Sandbox goes anywhere else. Bash and its children run in Seatbelt: they write only in the
/// Sessione's folder, the temporary folder and the package caches, reach only the package registries, and cannot
/// read `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.netrc` or the variables that hold tokens.
nonisolated struct SandboxPolicy: Equatable, Sendable {
    /// The package registries that sandboxed commands reach without asking, always: the preset. Never `github.com`:
    /// the proxy reads only the host name, so a domain that wide lets anything out.
    static let presetDomains = ["registry.npmjs.org", "registry.yarnpkg.com", "pypi.org", "files.pythonhosted.org",
                                "crates.io", "index.crates.io", "static.crates.io", "rubygems.org", "index.rubygems.org"]

    /// The package caches in the home folder that sandboxed commands write in, at each tool's default place on macOS:
    /// the folders of the preset.
    ///
    /// Only the caches, never a tool's whole folder: `~/.cargo/bin`, `~/.bun/bin`, `~/go/bin` and the tools' settings
    /// hold code that runs outside the Sandbox. Cargo also locks and records its caches in files of `~/.cargo`.
    /// Xcode's DerivedData stays out: the system note asks for `-derivedDataPath .build/DerivedData` instead.
    static let presetFolders = [
        ".npm",                                           // npm
        "Library/pnpm/store", "Library/Caches/pnpm",      // pnpm
        "Library/Caches/Yarn", ".yarn/berry",             // Yarn 1, Yarn 2 and later
        ".bun/install/cache",                             // Bun
        ".cargo/registry", ".cargo/git", ".cargo/.package-cache", ".cargo/.package-cache-mutate",
        ".cargo/.global-cache", ".cargo/.global-cache-journal", // Cargo
        "Library/Caches/pip", ".cache/uv",                // pip, uv
        "go/pkg/mod", "Library/Caches/go-build",          // Go
    ]

    /// The commands that run outside the Sandbox, in the syntax of the Bash Regole: always through a Richiesta or a
    /// Regola. `gh` reaches GitHub only from outside, since Go's TLS needs `trustd`.
    static let excludedCommands = ["gh", "gh *"]

    /// The hosts sandboxed commands reach without asking: the preset, then the Progetto's.
    let allowedDomains: [String]
    /// The folders sandboxed commands also write in, beyond the Sessione's own: the preset, then the Progetto's.
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
    ///   - allowances: The hosts and folders the user let the Progetto's Sandbox reach.
    init(environment: [String: String], userTemporaryFolder: String? = Self.darwinFolder(_CS_DARWIN_USER_TEMP_DIR),
         userCacheFolder: String? = Self.darwinFolder(_CS_DARWIN_USER_CACHE_DIR),
         allowances: SandboxAllowances = SandboxAllowances()) {
        let home = environment["HOME"] ?? NSHomeDirectory()
        let preset = [userTemporaryFolder, userCacheFolder].compactMap(\.self)
            + Self.presetFolders.map { "\(home)/\($0)" }
        writablePaths = preset + allowances.folders.filter { !preset.contains($0) }
        allowedDomains = Self.presetDomains + allowances.domains.filter { !Self.presetDomains.contains($0) }
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
    /// wants out of the Sandbox. A host outside `allowedDomains` becomes a Richiesta "Rete: host" (`strictAllowlist`
    /// off); only an Esecuzione, with nobody to ask, will deny it at once.
    var jsonObject: [String: Any] {
        [
            "enabled": true,
            "failIfUnavailable": true,
            "autoAllowBashIfSandboxed": true,
            "allowUnsandboxedCommands": true,
            "excludedCommands": Self.excludedCommands,
            "network": ["allowedDomains": allowedDomains, "allowLocalBinding": true, "strictAllowlist": false],
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
