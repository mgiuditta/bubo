import Foundation

/// Apri PR: the Sessione's work in one commit on its branch, `git push -u` of that branch, then `gh pr create
/// --head` into the branch it started from (spec 16).
///
/// Bubo pushes only here, at Crea PR, and never to a fork: `gh pr create --head` never pushes nor forks, and a push
/// GitHub refuses stops everything with its reason.
nonisolated struct PullRequestFlow: Sendable {
    /// The user's `gh`.
    var cli: GitHubCLI
    /// Runs git in the Sessione's worktree.
    var worktrees: WorktreeManager

    /// Where a Sessione's pull request goes.
    struct Target: Equatable, Sendable {
        /// The remote of the Progetto that points to the repo, such as `origin`.
        var remote: String
        var repository: GitHubRepository
        /// The Sessione's branch.
        var head: String
        /// The branch the Sessione started from, or the default one when it is not known.
        var base: String
        /// The default branch of the repo on GitHub.
        var defaultBranch: String
        /// Whether ``base`` is the default branch only because the Sessione did not keep the one it started from.
        var isBaseAssumed: Bool

        /// Whether the pull request goes into the default branch: only there `Closes` and `Fixes` close the issue.
        var isIntoDefaultBranch: Bool { base == defaultBranch }
    }

    /// Where the pull request of the Sessione working in `workspace` on `project` goes; asks GitHub only the default
    /// branch, and pushes nothing.
    ///
    /// - Throws: `PullRequestError.noBranch` outside the Sessione's own branch; `GitHubCLIError` when `gh` is missing,
    ///   not logged in, or the Progetto has no remote on GitHub.
    func target(of workspace: Workspace, in project: URL) async throws -> Target {
        guard let head = workspace.branch else { throw PullRequestError.noBranch }
        guard cli.executable != nil else { throw GitHubCLIError.missing }
        let (remote, repository) = try await cli.remote(of: project)
        let defaultBranch = try await cli.defaultBranch(of: repository)
        return Target(remote: remote, repository: repository, head: head, base: workspace.baseBranch ?? defaultBranch,
                      defaultBranch: defaultBranch, isBaseAssumed: workspace.baseBranch == nil)
    }

    /// What `gh pr create --dry-run` prints for `text`: nothing is committed, pushed or opened.
    ///
    /// - Throws: `GitHubCLIError`.
    func preview(_ text: PullRequestText, closing issue: IssueLink?, isDraft: Bool, to target: Target) async throws
        -> String {
        try await cli.createPullRequest(from: target.head, into: target.base, title: text.title,
                                        body: text.body(closing: issue), isDraft: isDraft, isDryRun: true,
                                        in: target.repository)
    }

    /// Crea PR: squashes the work of `workspace`, also what is not committed yet, into one commit on its branch,
    /// pushes the branch to the remote of `target`, and opens the pull request.
    ///
    /// - Returns: The pull request opened.
    /// - Throws: `PullRequestError` when there is nothing to propose or the push is refused;
    ///   `GitHubCLIError.missingWorkflowScope` when the push changes workflows without that scope; `GitHubCLIError`
    ///   when `gh` cannot open the pull request; `WorktreeError` when git fails.
    func open(_ text: PullRequestText, closing issue: IssueLink?, isDraft: Bool, from workspace: Workspace,
              to target: Target) async throws -> PullRequestLink {
        let body = text.body(closing: issue)
        try await squash(workspace, message: body.isEmpty ? text.title : text.title + "\n\n" + body)
        try await push(workspace, to: target)
        let output = try await cli.createPullRequest(from: target.head, into: target.base, title: text.title,
                                                     body: body, isDraft: isDraft, in: target.repository)
        guard let link = PullRequestLink(url: output, base: target.base) else {
            throw GitHubCLIError.failed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return link
    }

    /// Makes the work of `workspace` one commit with `message` on its branch, on top of the commit the branch started
    /// from; the files stay as they are.
    func squash(_ workspace: Workspace, message: String) async throws {
        let folder = workspace.folder
        try await worktrees.git(["add", "--all"], in: folder)
        let tree = try await worktrees.git(["write-tree"], in: folder).trimmingCharacters(in: .newlines)
        let tip = try await worktrees.run(["rev-parse", "--verify", "-q", "HEAD"], in: folder)
        let tipCommit = tip.exitCode == 0 ? tip.standardOutput.trimmingCharacters(in: .newlines) : nil
        if let base = workspace.base {
            let baseTree = try await worktrees.git(["rev-parse", "\(base)^{tree}"], in: folder)
                .trimmingCharacters(in: .newlines)
            guard tree != baseTree else { throw PullRequestError.nothingToPropose }
        }
        let parent = workspace.base.map { ["-p", $0] } ?? []
        let commit = try await worktrees.git(["commit-tree", tree, "-m", message] + parent, in: folder)
            .trimmingCharacters(in: .newlines)
        try await worktrees.git(["update-ref", "-m", "Bubo: apri PR", "HEAD", commit] + (tipCommit.map { [$0] } ?? []),
                                in: folder)
    }

    /// Pushes the branch of `workspace` to the remote of `target` and makes it its upstream, never asking for a
    /// password: the login stays where the user put it.
    private func push(_ workspace: Workspace, to target: Target) async throws {
        let branch = target.head
        let output = try await worktrees.runner.run(URL(filePath: "/usr/bin/env"), [
            "GIT_TERMINAL_PROMPT=0", "/usr/bin/git", "-C", workspace.folder.path, "push", "--force-with-lease",
            "--set-upstream", target.remote, "refs/heads/\(branch):refs/heads/\(branch)",
        ])
        guard output.exitCode != 0 else { return }
        let message = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scope = GitHubCLIError(pushError: message, host: target.repository.host) { throw scope }
        throw PullRequestError.pushRefused(message)
    }
}

/// Why Apri PR cannot go ahead.
nonisolated enum PullRequestError: LocalizedError, Equatable {
    /// The Sessione has no branch of its own.
    case noBranch
    /// The Sessione's branch has nothing the branch it started from lacks.
    case nothingToPropose
    /// The remote refused the push, with what git wrote.
    case pushRefused(String)

    var errorDescription: String? {
        switch self {
        case .noBranch:
            String(localized: "La Sessione non ha un branch suo: non c'è niente da proporre in una PR.")
        case .nothingToPropose:
            String(localized: "La Sessione non ha modifiche rispetto al branch da cui è partita.")
        case let .pushRefused(message):
            String(localized: "Il push del branch non è riuscito, e Bubo non crea fork. Controlla di avere i permessi di scrittura sul repo, poi riprova.\n\(message)")
        }
    }
}
