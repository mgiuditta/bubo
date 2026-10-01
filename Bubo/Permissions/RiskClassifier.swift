import Foundation

/// Gives a Richiesta di permesso its Livello di rischio, from the tool, the command and the path.
///
/// It errs high: a command it cannot read is Distruttivo locale, an unknown program Modifica reversibile.
/// It is not a security boundary: `claude`'s own rules and checks still run first; this decides how hard
/// approving is, and refuses the removals `claude` itself never lets anyone approve.
nonisolated struct RiskClassifier {
    /// The Sessione's folder, where relative paths start.
    let workingDirectory: String
    let home: String

    init(workingDirectory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.workingDirectory = Self.normalized(workingDirectory.path)
        self.home = Self.normalized(home.path)
    }

    /// The risk of `request`.
    func risk(of request: PermissionRequest) -> Risk {
        var risk: Risk
        switch request.tool {
        case "Bash":
            risk = request.command.map(risk(ofCommand:)) ?? Risk(level: .distruttivo)
        case "Read", "Glob", "Grep", "LS", "NotebookRead", "TodoWrite", "Task", "Agent":
            risk = Risk(level: .lettura)
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            let path = request.path.flatMap(resolved)
            let isInside = path.map { $0 == workingDirectory || $0.hasPrefix(workingDirectory + "/") } ?? false
            risk = Risk(level: !isInside || path.map(isProtected) == true ? .distruttivo : .modifica)
        case "WebFetch", "WebSearch":
            risk = Risk(level: .rete)
        case let tool where tool.hasPrefix("mcp__"):
            risk = Risk(level: request.mcpSource == "sdk" ? .lettura : .rete)
        default:
            risk = Risk(level: .modifica)
        }
        if [request.path, request.blockedPath].contains(where: { $0.flatMap(resolved).map(isSecret) == true }) {
            risk = risk.merged(with: Risk(level: .distruttivo))
        }
        return risk
    }

    /// The risk of the shell command `command`: the highest of the commands it would run.
    func risk(ofCommand command: String) -> Risk {
        guard let shell = ShellCommand(command) else { return Risk(level: .distruttivo) }
        var risk = shell.substitutions.reduce(Risk(level: .lettura)) { $0.merged(with: self.risk(ofCommand: $1)) }
        // Something downloaded and then run: `curl … | sh`, `bash <(curl …)`, `sh -c "$(curl …)"`.
        let downloadsInSubstitution = shell.substitutions.contains { ShellCommand($0)?.commands.contains(where: \.isDownload) == true }
        var isDownloading = false
        for simple in shell.commands {
            if Self.interpreters.contains(simple.program ?? "") || ["eval", "source", "."].contains(simple.program ?? "") {
                if isDownloading || (downloadsInSubstitution && simple.words.contains(where: \.isDynamic)) {
                    risk = risk.merged(with: Risk(level: .irreversibile))
                }
            }
            isDownloading = simple.pipesIntoNext && (isDownloading || simple.isDownload)
            risk = risk.merged(with: self.risk(of: simple))
        }
        return risk
    }

    private func risk(of simple: ShellCommand.Simple) -> Risk {
        simple.outputs.reduce(risk(ofWords: simple.words[...])) { risk, output in
            let level: RiskLevel
            if ["/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty"].contains(output.text) {
                level = .lettura
            } else if output.text.hasPrefix("/dev/") {
                level = .irreversibile
            } else {
                level = resolved(output).map(isProtected) == true ? .distruttivo : .modifica
            }
            return risk.merged(with: Risk(level: level))
        }
    }

    /// The risk of the simple command made of `words`, wrappers such as `sudo` and `env` included.
    private func risk(ofWords words: ArraySlice<ShellCommand.Word>) -> Risk {
        let words = words.drop { word in
            Self.reservedWords.contains(word.text) || word.text.wholeMatch(of: /[A-Za-z_][A-Za-z0-9_]*=.*/) != nil
        }
        guard let first = words.first else { return Risk(level: .lettura) }
        // `$EDITOR file`: no telling what runs.
        guard !first.isDynamic else { return Risk(level: .distruttivo) }
        let program = Self.program(first.text)
        let arguments = words.dropFirst()
        // Reading a secret, even with `cat`, can send it anywhere next.
        let readsSecret = arguments.contains { $0.looksLikePath && resolved($0).map(isSecret) == true }
        let risk = risk(ofProgram: program, arguments: arguments)
        return readsSecret ? risk.merged(with: Risk(level: .distruttivo)) : risk
    }

    private func risk(ofProgram program: String, arguments: ArraySlice<ShellCommand.Word>) -> Risk {
        let texts = arguments.map(\.text)
        let operands = Self.operands(arguments)
        func level(_ level: RiskLevel) -> Risk { Risk(level: level) }
        func writes(_ targets: [ShellCommand.Word], otherwise: RiskLevel = .modifica) -> Risk {
            level(targets.contains { resolved($0).map(isProtected) == true } ? .distruttivo : otherwise)
        }

        switch program {
        case "for", "case", "select", "function", "[[", "fi", "done", "esac", "}":
            return level(.lettura)
        case "sudo", "doas":
            return risk(ofWords: Self.dropOptions(arguments, takingValue: ["-u", "-g", "-C", "-h", "-p", "-U", "-r", "-t"]))
                .merged(with: level(.distruttivo))
        case "env":
            return risk(ofWords: Self.dropOptions(arguments, takingValue: ["-u", "-S", "-P", "-C"]))
        case "timeout", "gtimeout":
            return risk(ofWords: Self.dropOptions(arguments, takingValue: ["-s", "-k", "--signal", "--kill-after"]).dropFirst())
        case "nice", "nohup", "time", "command", "builtin", "exec", "stdbuf", "caffeinate", "noglob":
            return risk(ofWords: Self.dropOptions(arguments, takingValue: ["-n"]))
        case "xargs":
            let command = Self.dropOptions(arguments, takingValue: ["-n", "-I", "-L", "-P", "-d", "-E", "-s", "-J", "-R", "-S"])
            return command.isEmpty ? level(.lettura) : risk(ofWords: command)
        case let shell where Self.shells.contains(shell):
            guard let flag = arguments.firstIndex(where: { $0.text.hasPrefix("-") && !$0.text.hasPrefix("--") && $0.text.contains("c") }),
                  arguments.index(after: flag) < arguments.endIndex
            else { return level(.modifica) }
            let script = arguments[arguments.index(after: flag)]
            return script.isDynamic ? level(.distruttivo) : risk(ofCommand: script.text)
        case "eval":
            return arguments.contains(where: \.isDynamic) ? level(.distruttivo) : risk(ofCommand: texts.joined(separator: " "))
        case "rm", "rmdir", "unlink", "shred", "srm":
            return operands.contains(where: isCriticalTarget) ? .critical : level(.distruttivo)
        case "find":
            if let exec = texts.firstIndex(where: { ["-exec", "-execdir", "-ok", "-okdir"].contains($0) }) {
                let command = arguments.dropFirst(exec + 1).prefix { $0.text != ";" && $0.text != "+" }
                return risk(ofWords: command)
            }
            return level(texts.contains("-delete") ? .distruttivo : .lettura)
        case "git":
            return gitRisk(Self.dropOptions(arguments, takingValue: ["-C", "-c", "--git-dir", "--work-tree", "--namespace"]))
        case "gh":
            return ghRisk(operands.map(\.text), texts: texts)
        case "sed":
            return texts.contains { $0.hasPrefix("-i") || $0 == "--in-place" } ? writes(operands) : level(.lettura)
        case "tee", "cp", "mv", "ln", "touch", "mkdir", "install", "patch":
            return writes(operands)
        case "truncate", "killall", "pkill", "launchctl", "crontab", "shutdown", "reboot", "halt", "security", "csrutil",
             "spctl", "tmutil", "osascript":
            return level(.distruttivo)
        case "chmod", "chown", "chgrp":
            return texts.contains("-R") ? level(.distruttivo) : writes(operands)
        case "defaults":
            return level(texts.first == "delete" ? .distruttivo : texts.first == "read" ? .lettura : .modifica)
        case "dd":
            return level(texts.contains { $0.hasPrefix("of=/dev/") } ? .irreversibile : .distruttivo)
        case "diskutil":
            let verbs = ["erase", "partition", "zero", "reformat", "secureerase"]
            let erases = texts.contains { text in verbs.contains { text.lowercased().contains($0) } }
            return level(erases ? .irreversibile : .modifica)
        case let disk where disk.hasPrefix("mkfs") || disk.hasPrefix("newfs") || ["fdisk", "gpt"].contains(disk):
            return level(.irreversibile)
        case "mail", "mailx", "sendmail", "mutt":
            return level(.irreversibile)
        case "npm", "pnpm", "yarn", "bun", "cargo", "gem", "pip", "pip3", "uv", "pod", "twine", "swift":
            return packageRisk(operands.map(\.text))
        case "brew":
            let verb = operands.first?.text ?? ""
            if ["uninstall", "remove", "rm"].contains(verb) { return level(.distruttivo) }
            return level(["install", "upgrade", "update", "tap", "reinstall", "fetch"].contains(verb) ? .rete : .modifica)
        case "docker", "podman":
            let verb = operands.first?.text ?? ""
            if verb == "push" { return level(.irreversibile) }
            if ["rm", "rmi", "prune", "kill"].contains(verb) || texts.contains("prune") { return level(.distruttivo) }
            return level(["pull", "login", "run", "build"].contains(verb) ? .rete : .modifica)
        case "terraform", "tofu", "pulumi":
            return level(["destroy", "apply", "up", "import", "refresh"].contains(operands.first?.text ?? "") ? .irreversibile : .rete)
        case "kubectl", "helm":
            let changes = ["delete", "apply", "replace", "patch", "scale", "drain", "cordon", "uninstall", "install", "upgrade",
                           "rollback", "create", "edit", "rollout"]
            return level(changes.contains(operands.first?.text ?? "") ? .irreversibile : .rete)
        case "aws", "gcloud", "az", "gsutil", "firebase", "vercel", "netlify", "fly", "flyctl", "heroku", "wrangler":
            let changes = ["rm", "delete", "remove", "terminate", "destroy", "deploy", "purge", "rb"]
            return level(texts.contains { text in changes.contains { text.lowercased().contains($0) } } ? .irreversibile : .rete)
        case let network where Self.network.contains(network):
            return level(.rete)
        case let reader where Self.readers.contains(reader):
            return level(.lettura)
        default:
            return level(.modifica)
        }
    }

    private func gitRisk(_ arguments: ArraySlice<ShellCommand.Word>) -> Risk {
        guard let command = arguments.first?.text else { return Risk(level: .lettura) }
        let texts = arguments.dropFirst().map(\.text)
        let operands = texts.filter { !$0.hasPrefix("-") }
        /// Whether a flag is there, alone (`--force`) or in a cluster of short ones (`-fu`).
        func has(_ long: String, short: Character? = nil) -> Bool {
            texts.contains { text in
                if text == long || text.hasPrefix(long + "=") { return true }
                guard let short, text.wholeMatch(of: /-[A-Za-z]+/) != nil else { return false }
                return text.contains(short)
            }
        }
        let level: RiskLevel = switch command {
        case "status", "log", "diff", "show", "blame", "ls-files", "ls-tree", "rev-parse", "rev-list", "describe",
             "shortlog", "grep", "cat-file", "show-ref", "whatchanged", "version", "help", "check-ignore", "merge-base":
            .lettura
        case "fetch", "pull", "clone", "ls-remote", "submodule":
            .rete
        case "push":
            has("--force", short: "f") || has("--force-with-lease") || has("--force-if-includes") || has("--mirror")
                || has("--delete", short: "d") || has("--prune") || operands.dropFirst().contains { $0.hasPrefix("+") || $0.hasPrefix(":") }
                ? .irreversibile : .rete
        case "reset":
            has("--hard") || has("--merge") || has("--keep") ? .distruttivo : .modifica
        case "clean":
            has("--dry-run", short: "n") && !has("--force", short: "f") ? .lettura : .distruttivo
        case "checkout":
            texts.contains("--") || operands.contains(".") || has("--force", short: "f") ? .distruttivo : .modifica
        case "restore":
            has("--staged", short: "S") && !has("--worktree", short: "W") ? .modifica : .distruttivo
        case "switch":
            has("--discard-changes") || has("--force", short: "f") ? .distruttivo : .modifica
        case "stash":
            ["drop", "clear"].contains(operands.first ?? "") ? .distruttivo
                : ["list", "show"].contains(operands.first ?? "") ? .lettura : .modifica
        case "branch":
            has("--delete", short: "d") || has("-D") ? .distruttivo : texts.isEmpty || has("--list", short: "l") || has("-v") || has("-a") ? .lettura : .modifica
        case "tag", "remote", "config", "worktree":
            texts.isEmpty || has("--list", short: "l") || has("-v") || has("--get") ? .lettura : .modifica
        case "reflog":
            ["expire", "delete"].contains(operands.first ?? "") ? .distruttivo : .lettura
        case "filter-branch", "filter-repo":
            .distruttivo
        case "gc":
            has("--prune") ? .distruttivo : .modifica
        case "update-ref":
            has("-d") ? .distruttivo : .modifica
        default:
            .modifica
        }
        return Risk(level: level)
    }

    private func ghRisk(_ operands: [String], texts: [String]) -> Risk {
        let command = operands.prefix(2).joined(separator: " ")
        if ["pr merge", "repo delete", "repo archive", "release delete", "issue delete", "secret delete", "workflow run"]
            .contains(command) {
            return Risk(level: .irreversibile)
        }
        // `gh api` reads with GET, its default; any other method changes something on GitHub.
        if operands.first == "api", let method = texts.firstIndex(where: { $0 == "-X" || $0 == "--method" }),
           method + 1 < texts.count, texts[method + 1].uppercased() != "GET" {
            return Risk(level: .irreversibile)
        }
        return Risk(level: .rete)
    }

    private func packageRisk(_ operands: [String]) -> Risk {
        let verb = operands.first ?? ""
        if verb == "publish" || verb == "upload" || operands.prefix(2) == ["trunk", "push"] || (verb == "push") {
            return Risk(level: .irreversibile)
        }
        let fetches = ["install", "i", "add", "ci", "update", "upgrade", "up", "fetch", "sync", "dlx", "x", "exec", "create"]
        return Risk(level: fetches.contains(verb) ? .rete : .modifica)
    }

    // MARK: Paths

    /// Whether removing `word` would remove a critical path: the root, a top-level folder, the home folder or one
    /// above it, the working folder or one above it, everything in one of those (`*`), or an unguarded variable.
    private func isCriticalTarget(_ word: ShellCommand.Word) -> Bool {
        if word.isDynamic { return word.isWholeExpansion }
        var text = word.text
        // `dir/*` and `dir/.*` empty `dir`: as critical as `dir` itself.
        while let stripped = ["/*", "/.*", "/"].lazy.compactMap({ text.hasSuffix($0) ? String(text.dropLast($0.count)) : nil }).first {
            text = stripped
        }
        if text.isEmpty { return true }
        if text == "*" || text == ".*" { text = "." }
        guard let path = resolved(text) else { return true }
        let protectedPaths = ["/", home, workingDirectory]
        return path.split(separator: "/").count <= 1
            || protectedPaths.contains { $0.isWithin(path) }
    }

    /// Where `word` points, or `nil` when the shell decides it.
    private func resolved(_ word: ShellCommand.Word) -> String? {
        word.isDynamic ? nil : resolved(word.text)
    }

    /// `text` as an absolute path: `~` is the home folder, a relative path starts in the working folder;
    /// `nil` for another user's home.
    private func resolved(_ text: String) -> String? {
        if text == "~" { return home }
        if text.hasPrefix("~/") { return Self.normalized(home + text.dropFirst()) }
        if text.hasPrefix("~") { return nil }
        return Self.normalized(text.hasPrefix("/") ? text : workingDirectory + "/" + text)
    }

    /// Paths that hold credentials: reading them is already dangerous.
    private static let secrets = [".ssh", ".aws", ".gnupg", ".netrc", ".config/gh", ".docker/config.json", ".kube",
                                  ".npmrc", ".pypirc", "Library/Keychains", ".claude/.credentials.json"]
    /// Paths in the home folder that change how the shell, git or Claude Code behave.
    private static let homeConfigurations = [".zshrc", ".zprofile", ".zshenv", ".zlogin", ".bashrc", ".bash_profile",
                                             ".profile", ".gitconfig", ".claude.json", ".claude", "Library/LaunchAgents"]
    /// Folders and files that `claude` protects wherever they are.
    private static let protectedNames: Set<Substring> = [".git", ".vscode", ".idea", ".husky", ".devcontainer", ".mcp.json"]
    private static let systemFolders = ["/etc", "/private/etc", "/System", "/Library", "/usr", "/bin", "/sbin", "/Applications"]

    private func isSecret(_ path: String) -> Bool {
        Self.secrets.contains { path.isWithin(home + "/" + $0) }
    }

    /// Whether writing to `path` is Distruttivo locale: a secret, a configuration, a protected folder, the system.
    private func isProtected(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        let isInClaude = components.indices.contains { index in
            components[index] == ".claude" && components.dropFirst(index + 1).first != "worktrees"
        }
        return isSecret(path)
            || Self.homeConfigurations.contains { path.isWithin(home + "/" + $0) }
            || Self.systemFolders.contains { path.isWithin($0) }
            || components.contains(where: Self.protectedNames.contains) || isInClaude
    }

    private static func normalized(_ path: String) -> String {
        let standardized = URL(filePath: path).standardized.path
        return standardized.count > 1 && standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
    }

    // MARK: Words

    private static let reservedWords: Set<String> = ["if", "then", "else", "elif", "do", "while", "until", "!", "{", "time"]
    static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "fish", "csh", "tcsh"]
    static let interpreters = shells.union(["python", "python3", "perl", "ruby", "node", "bun", "deno", "osascript", "php"])
    private static let network: Set<String> = ["curl", "wget", "ssh", "scp", "sftp", "rsync", "nc", "ncat", "telnet", "ftp",
                                               "http", "https", "ping", "dig", "nslookup", "host", "whois", "open"]
    private static let readers: Set<String> = [
        "ls", "cat", "head", "tail", "less", "more", "wc", "pwd", "echo", "printf", "which", "whereis", "type", "file", "stat",
        "du", "df", "grep", "egrep", "fgrep", "rg", "ag", "fd", "tree", "diff", "cmp", "sort", "uniq", "cut", "tr", "jq",
        "date", "whoami", "id", "uname", "printenv", "true", "false", "test", "[", "basename", "dirname", "realpath",
        "readlink", "sw_vers", "ps", "man", "lsof", "cd", "sleep", "column", "nl", "md5", "shasum", "xxd", "hexdump",
        "plutil", "mdfind", "git-lfs", "export", "set", "unset", "local", "read", "wait", "exit", "return",
    ]

    /// The program's name, without its folder: `/bin/rm` is `rm`.
    static func program(_ text: String) -> String {
        text.split(separator: "/").last.map(String.init) ?? text
    }

    /// `arguments` from the first that is not an option, skipping the value of those in `takingValue`.
    private static func dropOptions(_ arguments: ArraySlice<ShellCommand.Word>,
                                    takingValue: Set<String>) -> ArraySlice<ShellCommand.Word> {
        var rest = arguments
        while let first = rest.first {
            if first.text == "--" { return rest.dropFirst() }
            guard first.text.hasPrefix("-") || first.text.wholeMatch(of: /[A-Za-z_][A-Za-z0-9_]*=.*/) != nil else { break }
            rest = rest.dropFirst(takingValue.contains(first.text) ? 2 : 1)
        }
        return rest
    }

    /// The arguments that are not options; after `--`, all of them.
    private static func operands(_ arguments: ArraySlice<ShellCommand.Word>) -> [ShellCommand.Word] {
        guard let end = arguments.firstIndex(where: { $0.text == "--" }) else {
            return arguments.filter { !$0.text.hasPrefix("-") || $0.text == "-" }
        }
        return arguments[..<end].filter { !$0.text.hasPrefix("-") } + arguments[(end + 1)...]
    }
}

private nonisolated extension ShellCommand.Simple {
    /// The program the command runs, past assignments and wrappers' options.
    var program: String? {
        let words = words.drop { $0.text.contains("=") || $0.text.hasPrefix("-") || ["sudo", "env", "command", "exec", "nohup", "time"].contains($0.text) }
        return words.first.map { RiskClassifier.program($0.text) }
    }

    /// Whether the command downloads something to its output.
    var isDownload: Bool { ["curl", "wget", "fetch", "http", "https"].contains(program ?? "") }
}

private nonisolated extension ShellCommand.Word {
    /// Whether the word reads as a path, not as a plain argument.
    var looksLikePath: Bool { text.contains("/") || text.hasPrefix("~") || text.hasPrefix(".") }
}

private nonisolated extension String {
    /// Whether this path is `folder` or inside it.
    func isWithin(_ folder: String) -> Bool { self == folder || hasPrefix(folder + "/") }
}
