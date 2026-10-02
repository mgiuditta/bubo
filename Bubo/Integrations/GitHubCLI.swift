import Foundation

/// The user's GitHub CLI, run only when a gesture needs it, never at launch (spec 16).
///
/// Every call has `GH_PROMPT_DISABLED=1`, so `gh` never stops on a question, and `--repo HOST/OWNER/REPO` from the
/// Progetto's remote. Bubo never asks `gh` for its token: the login stays where the user put it.
nonisolated struct GitHubCLI: Sendable {
    /// The folders searched for `gh`, in order: they are also the `PATH` it runs with.
    var searchPath: [URL] = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin"]
        .map { URL(filePath: $0, directoryHint: .isDirectory) }
    /// The environment the user's basics are copied from; Bubo's own by default.
    var base = ProcessInfo.processInfo.environment
    /// Whether a file can run; the only file system access.
    var isExecutable: @Sendable (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    /// Makes the runner of `gh`, with exactly the environment given.
    var makeRunner: @Sendable ([String: String]) -> ProcessRunner = { ProcessRunner.live(environment: $0) }
    /// Runs git, to read the Progetto's remote.
    var git = ProcessRunner.live

    /// How many open issues ⌘I lists: `gh` alone stops at 30.
    static let issueLimit = 100

    /// The `gh` found in ``searchPath``; `nil` when there is none.
    var executable: URL? {
        searchPath.map { $0.appending(path: "gh") }.first(where: isExecutable)
    }

    /// The environment of `gh` for `repository`: the user's basics, ``searchPath``, no prompts, no update checks, and
    /// the repo's host.
    func environment(for repository: GitHubRepository) -> [String: String] {
        var environment = base.filter { ChildEnvironment.copied.contains($0.key) }
        environment["PATH"] = searchPath.map { $0.path(percentEncoded: false).trimmingSuffix("/") }
            .joined(separator: ":")
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_NO_UPDATE_NOTIFIER"] = "1"
        environment["NO_COLOR"] = "1"
        environment["GH_HOST"] = repository.host
        return environment
    }

    /// The GitHub repo of `project`, from its `origin` remote, or its first one without `origin`.
    ///
    /// - Throws: `GitHubCLIError.noGitHubRemote` when no remote points to a repo on a host.
    func repository(of project: URL) async throws -> GitHubRepository {
        try await remote(of: project).repository
    }

    /// The remote of `project` that points to its GitHub repo, with the repo: `origin`, or its first one without
    /// `origin`.
    ///
    /// - Throws: `GitHubCLIError.noGitHubRemote` when no remote points to a repo on a host.
    func remote(of project: URL) async throws -> (name: String, repository: GitHubRepository) {
        let output = try await git.run(URL(filePath: "/usr/bin/git"), ["-C", project.path, "remote", "-v"])
        let remotes = output.standardOutput.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.count >= 2 ? (name: String(fields[0]), url: String(fields[1])) : nil
        }
        let ordered = remotes.filter { $0.name == "origin" } + remotes.filter { $0.name != "origin" }
        guard output.exitCode == 0,
              let found = ordered.lazy.compactMap({ remote in
                  GitHubRepository(remote: remote.url).map { (name: remote.name, repository: $0) }
              }).first
        else { throw GitHubCLIError.noGitHubRemote }
        return found
    }

    /// The open issues of `repository`, the most recently updated first, those matching `search` when it is not empty.
    ///
    /// - Throws: `GitHubCLIError`.
    func openIssues(of repository: GitHubRepository, matching search: String = "") async throws -> [GitHubIssue] {
        var arguments = ["issue", "list", "--repo", repository.argument, "--state", "open",
                         "--limit", String(Self.issueLimit), "--json", GitHubIssue.fields]
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty { arguments += ["--search", search] }
        return try decoder.decode([GitHubIssue].self, from: try await run(arguments, for: repository))
    }

    /// The title, text, comments, labels and URL of issue `number` of `repository`.
    ///
    /// - Throws: `GitHubCLIError`.
    func context(ofIssue number: Int, in repository: GitHubRepository) async throws -> GitHubIssueContext {
        let arguments = ["issue", "view", String(number), "--repo", repository.argument,
                         "--json", GitHubIssueContext.fields]
        return try decoder.decode(GitHubIssueContext.self, from: try await run(arguments, for: repository))
    }

    /// The name of the default branch of `repository`, such as `main`.
    ///
    /// - Throws: `GitHubCLIError`.
    func defaultBranch(of repository: GitHubRepository) async throws -> String {
        let arguments = ["repo", "view", repository.argument, "--json", "defaultBranchRef",
                         "--jq", ".defaultBranchRef.name"]
        let name = String(decoding: try await run(arguments, for: repository), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw GitHubCLIError.failed("") }
        return name
    }

    /// Opens a pull request on `repository` from `head` into `base`, a branch already pushed there: never a push,
    /// never a fork. With `isDryRun`, `gh` only prints what it would open.
    ///
    /// - Returns: What `gh` wrote: the URL of the pull request, or with `isDryRun` its details.
    /// - Throws: `GitHubCLIError`.
    func createPullRequest(from head: String, into base: String, title: String, body: String, isDraft: Bool,
                           isDryRun: Bool = false, in repository: GitHubRepository) async throws -> String {
        var arguments = ["pr", "create", "--repo", repository.argument, "--head", head, "--base", base,
                         "--title", title, "--body", body]
        if isDraft { arguments.append("--draft") }
        if isDryRun { arguments.append("--dry-run") }
        return String(decoding: try await run(arguments, for: repository), as: UTF8.self)
    }

    /// The state, the checks and the URL of pull request `number` of `repository`.
    ///
    /// - Throws: `GitHubCLIError`.
    func pullRequest(_ number: Int, in repository: GitHubRepository) async throws -> GitHubPullRequest {
        let arguments = ["pr", "view", String(number), "--repo", repository.argument, "--json", GitHubPullRequest.fields]
        return try decoder.decode(GitHubPullRequest.self, from: try await run(arguments, for: repository))
    }

    /// The log of the failed steps of GitHub Actions job `job` of `repository`.
    ///
    /// - Throws: `GitHubCLIError`.
    func failedLog(ofJob job: Int, in repository: GitHubRepository) async throws -> String {
        let arguments = ["run", "view", "--job", String(job), "--log-failed", "--repo", repository.argument]
        return String(decoding: try await run(arguments, for: repository), as: UTF8.self)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Runs `gh` with `arguments` and returns what it wrote on standard output.
    private func run(_ arguments: [String], for repository: GitHubRepository) async throws -> Data {
        guard let executable else { throw GitHubCLIError.missing }
        let output = try await makeRunner(environment(for: repository)).run(executable, arguments)
        switch output.exitCode {
        case 0: return Data(output.standardOutput.utf8)
        // gh's code for "this command requires authentication".
        case 4: throw GitHubCLIError.notAuthenticated(host: repository.host)
        default: throw GitHubCLIError.failed(output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// Why `gh` could not answer.
nonisolated enum GitHubCLIError: LocalizedError, Equatable {
    /// `gh` is not installed where Bubo looks.
    case missing
    /// `gh` has no login for `host`.
    case notAuthenticated(host: String)
    /// The Progetto has no remote on GitHub.
    case noGitHubRemote
    /// `gh` failed, with what it wrote on standard error.
    case failed(String)
    /// GitHub refused a push that changes `.github/workflows/`: the login of `gh` on `host` lacks the `workflow` scope.
    case missingWorkflowScope(host: String)

    /// The refusal of a `git push` to `host` for the `workflow` scope, from what git wrote on standard error; `nil`
    /// for any other failure.
    ///
    /// GitHub says it both for the OAuth login of `gh` and for a token: "refusing to allow an OAuth App to create or
    /// update workflow `…` without `workflow` scope".
    init?(pushError standardError: String, host: String) {
        guard standardError.contains("without `workflow` scope") else { return nil }
        self = .missingWorkflowScope(host: host)
    }

    /// The command that fixes this in a terminal, for the user to run: Bubo types it and never runs it on its own;
    /// `nil` when no command does.
    var remedy: String? {
        switch self {
        case .missing: "brew install gh"
        case let .notAuthenticated(host): "gh auth login" + Self.hostname(host)
        case let .missingWorkflowScope(host): "gh auth refresh -s workflow" + Self.hostname(host)
        case .noGitHubRemote, .failed: nil
        }
    }

    /// `--hostname` for a host other than github.com, gh's default; nothing for a host a shell could misread.
    private static func hostname(_ host: String) -> String {
        let isPlain = !host.isEmpty && host.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-".contains($0)) }
        return host != "github.com" && isPlain ? " --hostname \(host)" : ""
    }

    var errorDescription: String? {
        switch self {
        case .missing:
            String(localized: "Non trovo GitHub CLI in /opt/homebrew/bin, /usr/local/bin o /opt/local/bin. Installala con «brew install gh» nel Terminale, poi riprova.")
        case let .notAuthenticated(host):
            String(localized: "GitHub CLI non ha un accesso a \(host). Accedi con «gh auth login» nel Terminale, poi riprova. Un token messo solo in GH_TOKEN nel profilo della shell non arriva a Bubo.")
        case .noGitHubRemote:
            String(localized: "Il Progetto non ha un remoto su GitHub.")
        case let .failed(message):
            message.isEmpty ? String(localized: "GitHub CLI non ha risposto.") : message
        case .missingWorkflowScope:
            String(localized: "GitHub ha rifiutato il push perché cambia .github/workflows e l'accesso di GitHub CLI non ha il permesso «workflow». Aggiungilo con «gh auth refresh -s workflow» nel Terminale, poi riprova.")
        }
    }
}

private extension String {
    nonisolated func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) && count > 1 ? String(dropLast(suffix.count)) : self
    }
}
