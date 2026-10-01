import Foundation

/// Errors from changing the Regole di permesso of a Progetto.
nonisolated enum RuleStoreError: Error, Equatable {
    /// The Progetto is not trusted: `claude` loads only the user's settings there, so it would not read the rule.
    case untrusted
    /// The settings file, its `permissions` or its `allow` is not what the CLI writes: Bubo does not touch it.
    case unreadableSettings
    /// `.claude` or the settings file is a link, or leads outside the Progetto: Bubo never writes through it.
    case unsafeLocation
    /// The CLI kept overwriting the file while Bubo wrote it.
    case overwritten
}

/// The Regole di permesso a Progetto allows (#79): its own, in `.claude/settings.local.json` of the main checkout,
/// which `claude` reads in every worktree of the Progetto and in the terminal; the shared ones in `.claude/settings.json`
/// and the user's in `~/.claude/settings.json`, only listed.
///
/// Bubo writes only `permissions.allow` of the Progetto's own file, atomically, and leaves every other key as it was.
nonisolated struct RuleStore: Sendable {
    /// Where a rule comes from.
    enum Origin: Sendable {
        /// The Progetto's own, not in git: the only rules Bubo changes.
        case local
        /// The Progetto's shared ones, in git.
        case project
        /// The user's, in every Progetto.
        case user
    }

    /// A rule with the file it comes from.
    struct Entry: Hashable, Sendable {
        let rule: String
        let origin: Origin
    }

    /// The main checkout of the Progetto, as a real path.
    let root: URL
    /// The user's settings of `claude`, only read.
    var userSettings = URL.homeDirectory.appending(path: ".claude/settings.json")

    /// The rules of the Progetto in `folder`, or in the Progetto that `folder` is a worktree of.
    init(project folder: URL) {
        root = URL(filePath: TrustGate.root(of: folder), directoryHint: .isDirectory)
    }

    /// The file that "Sempre in questo Progetto" writes.
    var file: URL { root.appending(path: ".claude/settings.local.json") }

    private var sharedSettings: URL { root.appending(path: ".claude/settings.json") }

    /// The `permissions.allow` rules, the Progetto's own first, then the shared ones and the user's.
    ///
    /// A missing file adds nothing; an unreadable one is in `unreadableFiles`.
    var entries: [Entry] {
        [(file, Origin.local), (sharedSettings, .project), (userSettings, .user)].flatMap { url, origin in
            ((try? Self.allowRules(at: url)) ?? []).map { Entry(rule: $0, origin: origin) }
        }
    }

    /// The settings files whose rules `claude` skips because they cannot be read.
    var unreadableFiles: [URL] {
        [file, sharedSettings, userSettings].filter { url in
            do {
                _ = try Self.allowRules(at: url)
                return false
            } catch {
                return true
            }
        }
    }

    /// Adds `rule` to the Progetto's own rules, unless it is there already.
    ///
    /// - Throws: `RuleStoreError`, or a file error.
    func add(_ rule: String) throws {
        try change { rules in
            if !rules.contains(rule) { rules.append(rule) }
        }
    }

    /// Replaces the Progetto's own rule `old` with `new`, in the same place.
    ///
    /// - Throws: `RuleStoreError`, or a file error.
    func replace(_ old: String, with new: String) throws {
        try change { rules in
            guard let index = rules.firstIndex(of: old) else { return }
            if rules.contains(new) {
                rules.remove(at: index)
            } else {
                rules[index] = new
            }
        }
    }

    /// Removes `rule` from the Progetto's own rules: from the next call, `claude` asks again.
    ///
    /// - Throws: `RuleStoreError`, or a file error.
    func remove(_ rule: String) throws {
        try change { rules in rules.removeAll { $0 == rule } }
    }

    /// Changes `permissions.allow` of the Progetto's own file; reads it again and retries if the CLI undid the change.
    private func change(_ edit: (inout [String]) -> Void) throws {
        try checkLocation()
        for _ in 0..<3 {
            var settings = try Self.object(at: file) ?? [:]
            var permissions = try Self.value(settings["permissions"], or: [String: Any]())
            var rules = try Self.value(permissions["allow"], or: [String]())
            edit(&rules)
            permissions["allow"] = rules
            settings["permissions"] = permissions
            try write(settings)
            if try Self.allowRules(at: file) == rules { return }
        }
        throw RuleStoreError.overwritten
    }

    /// Makes sure `.claude` is a real folder of the Progetto and the file is not a link, creating the folder if missing.
    ///
    /// A repo could ship them as links into `~/.claude` or anywhere else: writing through one would change another file.
    private func checkLocation() throws {
        // The home folder's `.claude` is the user's own configuration, never a Progetto's.
        let rootPath = TrustGate.realPath(root.path)
        guard rootPath != TrustGate.realPath(URL.homeDirectory.path) else { throw RuleStoreError.unsafeLocation }
        let folder = file.deletingLastPathComponent().path
        var status = stat()
        if lstat(folder, &status) != 0 {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
        } else if status.st_mode & S_IFMT != S_IFDIR {
            throw RuleStoreError.unsafeLocation
        }
        guard TrustGate.realPath(folder) == rootPath + "/.claude" else { throw RuleStoreError.unsafeLocation }
        if lstat(file.path, &status) == 0, status.st_mode & S_IFMT != S_IFREG {
            throw RuleStoreError.unsafeLocation
        }
    }

    /// Replaces the file atomically, keeping its permissions; a new file is readable by everyone like the CLI's.
    private func write(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let permissions = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions] ?? 0o644
        let temporary = file.deletingLastPathComponent().appending(path: ".settings.local.json.bubo-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data + Data("\n".utf8),
                                             attributes: [.posixPermissions: permissions])
        else { throw CocoaError(.fileWriteUnknown) }
        guard rename(temporary.path, file.path) == 0 else {
            let code = errno
            unlink(temporary.path)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    /// The `permissions.allow` rules of the file at `url`; none when it does not exist.
    private static func allowRules(at url: URL) throws -> [String] {
        guard let settings = try object(at: url) else { return [] }
        return try value(value(settings["permissions"], or: [String: Any]())["allow"], or: [String]())
    }

    /// `value` as a `T`, `empty` when missing; anything else is not what the CLI writes.
    private static func value<T>(_ value: Any?, or empty: T) throws -> T {
        guard let value else { return empty }
        guard let typed = value as? T else { throw RuleStoreError.unreadableSettings }
        return typed
    }

    /// The JSON object in the file at `url`, or `nil` when it does not exist.
    private static func object(at url: URL) throws -> [String: Any]? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RuleStoreError.unreadableSettings
        }
        return object
    }
}
