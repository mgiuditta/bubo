import Foundation

/// The Macchine of `~/.ssh/config`: the concrete aliases of its `Host` lines and of the files it includes, each
/// resolved by OpenSSH with `ssh -G`.
///
/// `ssh -G` resolves one alias but lists none, so Bubo reads only the names after `Host` and `Include`: everything
/// else, user, hostname, port, `ProxyJump`, comes from OpenSSH. Patterns, with `*`, `?` or `!`, are left out.
nonisolated struct SSHConfigReader: Sendable {
    /// What the reader takes from the disk; tests pass fixtures.
    struct FileSystem: Sendable {
        /// The text of a file, or `nil` if it cannot be read.
        var contents: @Sendable (URL) -> String?
        /// The paths matching a glob pattern, in lexical order, as `Include` expands them.
        var paths: @Sendable (_ pattern: String) -> [String]

        /// The real disk.
        static let live = FileSystem(
            contents: { try? String(contentsOf: $0, encoding: .utf8) },
            paths: expandGlob
        )
    }

    /// The user's SSH folder, `~/.ssh`: relative `Include` paths start there.
    var sshFolder = URL.homeDirectory.appending(path: ".ssh", directoryHint: .isDirectory)
    var fileSystem = FileSystem.live
    /// Runs `ssh -G`.
    var runner = ProcessRunner.live

    /// The Macchine of the configuration, in the order of their `Host` lines; an alias `ssh -G` cannot resolve is
    /// left out.
    func machines() async -> [Machine] {
        var machines: [Machine] = []
        for alias in aliases() {
            guard let output = try? await runner.run(SSHCommand.executable, ["-G", "--", alias]),
                  output.exitCode == 0,
                  let machine = Self.machine(alias: alias, resolved: output.standardOutput)
            else { continue }
            machines.append(machine)
        }
        return machines
    }

    /// The concrete aliases of `~/.ssh/config` and of the files it includes, each once, in the order they appear.
    func aliases() -> [String] {
        var aliases: [String] = []
        var visited: Set<String> = []
        collectAliases(in: sshFolder.appending(path: "config").path, depth: 0, visited: &visited, into: &aliases)
        return aliases
    }

    private func collectAliases(in path: String, depth: Int, visited: inout Set<String>, into aliases: inout [String]) {
        // OpenSSH stops at 16 nested includes; Bubo also reads each file once, so a loop ends at once.
        guard depth < 16, visited.insert(path).inserted, let text = fileSystem.contents(URL(filePath: path))
        else { return }
        for line in text.split(whereSeparator: \.isNewline) {
            guard let (keyword, values) = Self.keywordAndValues(of: line) else { continue }
            switch keyword {
            case "host":
                for alias in values where Self.isConcrete(alias) && !aliases.contains(alias) {
                    aliases.append(alias)
                }
            case "include":
                for pattern in values {
                    for included in fileSystem.paths(includePath(pattern)) {
                        collectAliases(in: included, depth: depth + 1, visited: &visited, into: &aliases)
                    }
                }
            default:
                continue
            }
        }
    }

    /// An `Include` argument as a full path: `~` is the home, a relative path starts in `~/.ssh`.
    private func includePath(_ pattern: String) -> String {
        if pattern.hasPrefix("~/") {
            return sshFolder.deletingLastPathComponent().appending(path: String(pattern.dropFirst(2))).path
        }
        return pattern.hasPrefix("/") ? pattern : sshFolder.appending(path: pattern).path
    }

    /// The lowercased keyword of a configuration line and its arguments, unquoted; `nil` for a blank line or a
    /// comment.
    static func keywordAndValues(of line: Substring) -> (String, [String])? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        // "Keyword value", "Keyword=value" and "Keyword = value" are all valid.
        let separator = trimmed.firstIndex { $0 == "=" || $0.isWhitespace } ?? trimmed.endIndex
        let keyword = trimmed[..<separator].lowercased()
        let rest = trimmed[separator...].drop { $0 == "=" || $0.isWhitespace }
        return (keyword, arguments(in: rest))
    }

    /// The arguments of a line, split on blanks; a double-quoted argument may hold blanks.
    private static func arguments(in text: Substring) -> [String] {
        var arguments: [String] = []
        var current = ""
        var isQuoted = false
        for character in text {
            if character == "\"" {
                isQuoted.toggle()
            } else if character.isWhitespace && !isQuoted {
                if !current.isEmpty { arguments.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { arguments.append(current) }
        return arguments
    }

    /// Whether a `Host` argument names one host instead of matching many.
    static func isConcrete(_ alias: String) -> Bool {
        !alias.contains { "*?!".contains($0) }
    }

    /// The Macchina an alias resolves to, from the output of `ssh -G`; `nil` without a user or a hostname.
    static func machine(alias: String, resolved: String) -> Machine? {
        var options: [String: String] = [:]
        for line in resolved.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            if options[key] == nil { options[key] = String(parts[1]) }
        }
        guard let user = options["user"], let hostname = options["hostname"] else { return nil }
        return Machine(alias: alias, user: user, hostname: hostname, port: options["port"].flatMap(Int.init) ?? 22)
    }
}

/// The paths matching `pattern`, in lexical order, with `glob(3)`.
private nonisolated func expandGlob(_ pattern: String) -> [String] {
    var matches = glob_t()
    defer { globfree(&matches) }
    guard glob(pattern, 0, nil, &matches) == 0 else { return [] }
    return (0..<Int(matches.gl_pathc)).compactMap { index in
        matches.gl_pathv[index].map { String(cString: $0) }
    }
}
