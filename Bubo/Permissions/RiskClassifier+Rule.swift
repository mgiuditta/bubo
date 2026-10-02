import Foundation

nonisolated extension RiskClassifier {
    /// The highest risk among the calls the Regola di permesso `rule` would allow, such as `Bash(git push *)`.
    ///
    /// A rule is a pattern, not a call: each `*` is tried with arguments that raise the level of common programs
    /// (`--force`, `-rf /`, `push --force`, `-exec rm`, …), and a rule for a whole tool counts as its worst call.
    /// Like the classifier, it errs high; operators such as `;` and `&&` are left out, since `claude` matches each
    /// command of a line against the rules on its own.
    func risk(ofRule rule: String) -> Risk {
        let (tool, content) = Self.parts(of: rule)
        switch tool {
        case "Bash":
            guard var command = content else { return Risk(level: .irreversibile) }
            // The legacy prefix form: `npm run:*` is `npm run *`.
            if command.hasSuffix(":*") { command = String(command.dropLast(2)) + " *" }
            guard let wildcard = command.firstIndex(of: "*") else { return risk(ofCommand: command) }
            guard !command[..<wildcard].trimmingCharacters(in: .whitespaces).isEmpty else {
                return Risk(level: .irreversibile)
            }
            return Self.argumentProbes.reduce(Risk(level: .lettura)) { risk, probe in
                risk.merged(with: self.risk(ofCommand: command.replacing(/\*+/, with: probe)))
            }
        case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit", "NotebookRead", "Glob", "Grep", "LS":
            guard let content else {
                // Every file, the user's keys included; an edit outside the folder is already Distruttivo.
                return risk(of: PermissionRequest(id: "", tool: tool, path: home + "/.ssh/id_ed25519"))
            }
            return paths(ofPattern: content).reduce(Risk(level: .lettura)) { risk, path in
                risk.merged(with: self.risk(of: PermissionRequest(id: "", tool: tool, path: path)))
            }
        default:
            return risk(of: PermissionRequest(id: "", tool: tool))
        }
    }

    /// The paths that stand for the files the gitignore-style `pattern` of a file rule covers.
    ///
    /// `//p` is absolute, `~/p` in the home folder, `/p` either absolute or from the Progetto (both are tried),
    /// anything else from the Progetto. A wildcard over the home folder, or a folder above it, reaches its keys.
    private func paths(ofPattern pattern: String) -> [String] {
        let bases: [String] = if pattern.hasPrefix("//") {
            [String(pattern.dropFirst())]
        } else if pattern.hasPrefix("~/") || pattern == "~" {
            [home + pattern.dropFirst()]
        } else if pattern.hasPrefix("/") {
            [pattern, workingDirectory + pattern]
        } else {
            [workingDirectory + "/" + pattern]
        }
        return bases.flatMap { base -> [String] in
            guard let wildcard = base.firstIndex(of: "*") else { return [base] }
            var paths = ["x", ".ssh/id_ed25519"].map { base.replacing(/\*+/, with: $0) }
            let fixed = URL(filePath: String(base[..<wildcard])).standardized.path
            let folder = fixed.hasSuffix("/") ? fixed : (fixed as NSString).deletingLastPathComponent
            if home == folder || home.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/") {
                paths.append(home + "/.ssh/id_ed25519")
            }
            return paths
        }
    }

    /// The tool and the content of `rule` as `claude` reads it: an empty content or `*` is the whole tool, and `\(`,
    /// `\)` and `\\` are unescaped.
    static func parts(of rule: String) -> (tool: String, content: String?) {
        guard let open = rule.firstIndex(of: "("), rule.hasSuffix(")"), rule.index(before: rule.endIndex) > open else {
            return (rule, nil)
        }
        let raw = String(rule[rule.index(after: open)..<rule.index(before: rule.endIndex)])
        let content = raw.replacing("\\(", with: "(").replacing("\\)", with: ")").replacing("\\\\", with: "\\")
        return (String(rule[..<open]), content.isEmpty || content == "*" ? nil : content)
    }

    /// What each `*` of a command rule is tried with: arguments that make common programs reach levels 4–5.
    private static let argumentProbes = [
        "", "x", "-f", "--force", "/", "-rf /", "-rf ~", "--hard", "-D x", "-d x", "-delete", "-exec rm -rf / ;",
        "delete x", "drop", "clean -fdx", "reset --hard", "push --force", "x --force", "+x", "publish", "destroy",
        "apply", "deploy", "pr merge 1", "repo delete x", "-c 'rm -rf /'", "-X DELETE x",
    ]
}
