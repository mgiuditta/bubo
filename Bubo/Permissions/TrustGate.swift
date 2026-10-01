import Foundation

/// Errors from writing the trust of a folder.
nonisolated enum TrustGateError: Error, Equatable {
    /// `~/.claude.json` is not a JSON object: Bubo does not touch it.
    case unreadableConfiguration
    /// The CLI kept overwriting the value while Bubo wrote it.
    case overwritten
}

/// Decides whether `claude` may load a folder's own settings: hooks, `env`, `apiKeyHelper`,
/// `.mcp.json`, `settings.local.json` and `CLAUDE.md` (#266).
///
/// The only source of trust is the CLI's `~/.claude.json`: a folder is trusted when
/// `projects["<root>"].hasTrustDialogAccepted` is true, where the root is the main checkout of its
/// repo, even from a worktree. Bubo keeps no register of its own, so a folder trusted in the CLI is
/// trusted in Bubo, and the other way round.
nonisolated struct TrustGate: Sendable {
    /// The CLI's global configuration.
    var configuration = URL.homeDirectory.appending(path: ".claude.json")

    /// Whether `claude` may load the settings of `folder`.
    ///
    /// Like the CLI, a trusted parent within the same repo, or anywhere above a folder outside git,
    /// also counts.
    func isTrusted(_ folder: URL) -> Bool {
        guard let projects = (try? readConfiguration())?["projects"] as? [String: Any] else { return false }
        return Self.candidates(for: folder).contains { path in
            (projects[path] as? [String: Any])?["hasTrustDialogAccepted"] as? Bool == true
        }
    }

    /// The `settingSources` for a `claude` started in `folder`: the user's own only, until trusted.
    func settingSources(for folder: URL) -> [String] {
        isTrusted(folder) ? ["user", "project", "local"] : ["user"]
    }

    /// Trusts the root of `folder`, changing only its `hasTrustDialogAccepted` in `~/.claude.json`.
    ///
    /// - Throws: `TrustGateError`, or a file error.
    func trust(_ folder: URL) throws {
        try setTrust(true, for: folder)
    }

    /// Revokes the trust in the root of `folder`; it counts from the next `claude` started there.
    ///
    /// - Throws: `TrustGateError`, or a file error.
    func revoke(_ folder: URL) throws {
        try setTrust(false, for: folder)
    }

    /// The key of `folder` in `projects`: the main checkout of its repo, or the folder itself
    /// outside git, as a real path in NFC like the CLI writes it.
    static func root(of folder: URL) -> String {
        let path = realPath(folder.path)
        return repository(containing: path)?.mainCheckout ?? path
    }

    private func setTrust(_ isAccepted: Bool, for folder: URL) throws {
        let key = Self.root(of: folder)
        // The CLI rewrites the whole file on its own saves: read again and retry if it undid ours.
        for _ in 0..<3 {
            var configuration = try readConfiguration() ?? [:]
            var projects = configuration["projects"] as? [String: Any] ?? [:]
            var project = projects[key] as? [String: Any] ?? [:]
            project["hasTrustDialogAccepted"] = isAccepted
            projects[key] = project
            configuration["projects"] = projects
            try write(configuration)
            let saved = try readConfiguration()?["projects"] as? [String: Any]
            if (saved?[key] as? [String: Any])?["hasTrustDialogAccepted"] as? Bool == isAccepted { return }
        }
        throw TrustGateError.overwritten
    }

    /// The configuration, or `nil` when the file does not exist yet.
    private func readConfiguration() throws -> [String: Any]? {
        let data: Data
        do {
            data = try Data(contentsOf: configuration)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TrustGateError.unreadableConfiguration
        }
        return object
    }

    /// Replaces the file atomically, readable only by the user as the CLI leaves it, following a symlink.
    private func write(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes])
        let target = Self.realPath(configuration.path)
        let temporary = (target as NSString).deletingLastPathComponent + "/.claude.json.bubo-\(UUID().uuidString)"
        guard FileManager.default.createFile(atPath: temporary, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary, target) == 0 else {
            let code = errno
            unlink(temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    /// The keys that make `folder` trusted: its root, then the folder and its parents up to the top
    /// of its checkout, or up to `/` outside git.
    private static func candidates(for folder: URL) -> [String] {
        let path = realPath(folder.path)
        let repository = repository(containing: path)
        var candidates = [repository?.mainCheckout ?? path]
        var current = path
        while true {
            candidates.append(current)
            if current == repository?.top || current == "/" { return candidates }
            current = (current as NSString).deletingLastPathComponent
        }
    }

    /// The checkout containing `path` and the main checkout of its repo, read from `.git` without
    /// running git: in a worktree `.git` is a file that points into `<main>/.git/worktrees/<name>`.
    private static func repository(containing path: String) -> (top: String, mainCheckout: String)? {
        var top = path
        while true {
            let git = top + "/.git"
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: git, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return (top, top) }
                return (top, mainCheckout(ofWorktreeAt: top, gitFile: git) ?? top)
            }
            if top == "/" { return nil }
            top = (top as NSString).deletingLastPathComponent
        }
    }

    private static func mainCheckout(ofWorktreeAt top: String, gitFile: String) -> String? {
        guard let line = try? String(contentsOfFile: gitFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            line.hasPrefix("gitdir: ")
        else { return nil }
        let gitDirectory = absolute(String(line.dropFirst("gitdir: ".count)), from: top)
        // A submodule has no commondir: its own checkout is the root.
        guard let common = try? String(contentsOfFile: gitDirectory + "/commondir", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        let commonDirectory = realPath(absolute(common, from: gitDirectory))
        guard (commonDirectory as NSString).lastPathComponent == ".git" else { return nil }
        return (commonDirectory as NSString).deletingLastPathComponent
    }

    private static func absolute(_ path: String, from base: String) -> String {
        path.hasPrefix("/") ? path : (base as NSString).appendingPathComponent(path)
    }

    /// The path with symlinks resolved (`/tmp` is `/private/tmp`), as `getcwd` gives it to `claude`.
    static func realPath(_ path: String) -> String {
        let resolved = realpath(path, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        }
        return (resolved ?? (path as NSString).standardizingPath).precomposedStringWithCanonicalMapping
    }
}
