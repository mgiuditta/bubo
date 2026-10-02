import Foundation

/// The branch of a Consegna (spec 24, Formato `.bubo`): a `git bundle` of the Sessione's commits from the base, plus
/// one commit with the changes not committed yet, made with a temporary index.
///
/// The sender's worktree, index and branches are never written: the uncommitted changes go through a copy of the
/// index (`GIT_INDEX_FILE`, `git add -A`, `write-tree`, `commit-tree`), and the bundle through a temporary ref that
/// is deleted right after. Files git ignores never go out, since `git add -A` skips them.
nonisolated struct BranchBundler: Sendable {
    /// What git has of the Sessione's branch, read once for the foglio and then bundled as it was.
    struct Snapshot: Equatable, Sendable {
        /// The Sessione's branch.
        var branch: String
        /// The commit the bundle starts after: the merge-base with the remote's main branch, else the Sessione's base;
        /// `nil` bundles the whole history.
        var base: String?
        /// The branch's last commit.
        var head: String
        /// The tree of the worktree with its uncommitted changes, when it differs from `head`'s.
        var uncommittedTree: String?
        /// The commits from `base` to `head`.
        var commitCount: Int
        /// The files that differ from `base`, uncommitted changes included.
        var changedFiles: [String]
        /// The uncommitted changes as `git diff` shows them, for the scanner.
        var uncommittedDiff: String
        /// The URL of the `origin` remote, for the receiver to fetch a missing base; `nil` without one.
        var remote: String?

        /// Whether the worktree has changes not committed yet, new files included.
        var hasUncommittedChanges: Bool { uncommittedTree != nil }

        /// Whether the bundle would carry nothing the base does not have.
        var isEmpty: Bool { commitCount == 0 && !hasUncommittedChanges }
    }

    /// git failed, with what it wrote on standard error.
    struct Failure: Error, Equatable {
        var message: String
    }

    /// The name and email of the commit with the uncommitted changes: no address of the sender goes out with it.
    static let committerEmail = "consegna@bubo.invalid"

    /// Runs git.
    var runner = ProcessRunner.live

    private static let git = URL(filePath: "/usr/bin/git")

    /// Reads the branch `branch` checked out in `folder`, with `fallbackBase` when the remote has no main branch.
    ///
    /// - Throws: ``Failure`` when git fails.
    @concurrent func snapshot(of folder: URL, branch: String, fallbackBase: String?) async throws -> Snapshot {
        let head = try await git(["rev-parse", "HEAD"], in: folder).trimmed
        let base = await mergeBase(in: folder) ?? fallbackBase
        let index = try await temporaryIndex(of: folder)
        defer { try? FileManager.default.removeItem(at: index) }
        try await git(["add", "-A"], in: folder, index: index)
        let tree = try await git(["write-tree"], in: folder, index: index).trimmed
        let headTree = try await git(["rev-parse", "HEAD^{tree}"], in: folder).trimmed
        let uncommittedTree = tree == headTree ? nil : tree

        let count = try await git(["rev-list", "--count", base.map { "\($0)..HEAD" } ?? "HEAD"], in: folder)
        let changed = if let base {
            try await git(["-c", "core.quotePath=false", "diff", "--name-only", "--no-renames", base, tree], in: folder)
        } else {
            try await git(["-c", "core.quotePath=false", "ls-tree", "-r", "--name-only", tree], in: folder)
        }
        let diff = uncommittedTree == nil ? "" : try await git(
            ["-c", "core.quotePath=false", "diff", "--no-color", "--no-ext-diff", headTree, tree], in: folder
        )
        let remote = try? await git(["remote", "get-url", "origin"], in: folder).trimmed
        return Snapshot(
            branch: branch, base: base, head: head, uncommittedTree: uncommittedTree,
            commitCount: Int(count.trimmed) ?? 0,
            changedFiles: changed.split(separator: "\n").map(String.init),
            uncommittedDiff: diff, remote: remote?.isEmpty == false ? remote : nil
        )
    }

    /// Writes the bundle of `snapshot` at `file`: the commits after its base, and on top the uncommitted changes as a
    /// commit "Modifiche non salvate di ‹sender›".
    ///
    /// - Returns: The ref the bundle carries, which the receiver fetches; `nil`, with no file, when the snapshot
    ///   is empty.
    /// - Throws: ``Failure`` when git fails.
    @concurrent func bundle(_ snapshot: Snapshot, in folder: URL, sender: String, to file: URL) async throws -> String? {
        guard !snapshot.isEmpty else { return nil }
        var tip = snapshot.head
        if let tree = snapshot.uncommittedTree {
            let message = String(localized: "Modifiche non salvate di \(sender)")
            tip = try await git(["commit-tree", tree, "-p", snapshot.head, "-m", message], in: folder,
                                author: sender).trimmed
        }
        // A bundle of a bare commit is refused ("Refusing to create empty bundle"): it needs a ref.
        let ref = "refs/bubo/consegna-\(UUID().uuidString.lowercased())"
        try await git(["update-ref", ref, tip], in: folder)
        do {
            try await git(["bundle", "create", "--quiet", file.path, ref] + (snapshot.base.map { ["^\($0)"] } ?? []),
                          in: folder)
        } catch {
            _ = try? await git(["update-ref", "-d", ref], in: folder)
            throw error
        }
        try await git(["update-ref", "-d", ref], in: folder)
        return ref
    }

    /// The merge-base of `HEAD` with the remote's main branch, which the receiver most likely has.
    private func mergeBase(in folder: URL) async -> String? {
        for upstream in ["refs/remotes/origin/HEAD", "refs/remotes/origin/main", "refs/remotes/origin/master"] {
            if let base = try? await git(["merge-base", "HEAD", upstream], in: folder).trimmed, !base.isEmpty {
                return base
            }
        }
        return nil
    }

    /// A copy of the worktree's index in a temporary file, so `git add` finds the files it already knows.
    private func temporaryIndex(of folder: URL) async throws -> URL {
        let index = try await git(["rev-parse", "--path-format=absolute", "--git-path", "index"], in: folder).trimmed
        let copy = FileManager.default.temporaryDirectory.appending(path: "bubo-consegna-\(UUID().uuidString).index")
        if FileManager.default.fileExists(atPath: index) {
            try FileManager.default.copyItem(atPath: index, toPath: copy.path)
        }
        return copy
    }

    @discardableResult
    private func git(_ arguments: [String], in folder: URL, index: URL? = nil, author: String? = nil) async throws
        -> String {
        var environment: [String] = []
        if let index { environment.append("GIT_INDEX_FILE=\(index.path)") }
        if let author {
            environment += ["GIT_AUTHOR_NAME=\(author)", "GIT_AUTHOR_EMAIL=\(Self.committerEmail)",
                            "GIT_COMMITTER_NAME=\(author)", "GIT_COMMITTER_EMAIL=\(Self.committerEmail)"]
        }
        let output = if environment.isEmpty {
            try await runner.run(Self.git, ["-C", folder.path] + arguments)
        } else {
            try await runner.run(URL(filePath: "/usr/bin/env"), environment + [Self.git.path, "-C", folder.path] + arguments)
        }
        guard output.exitCode == 0 else { throw Failure(message: output.standardError) }
        return output.standardOutput
    }
}

private extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
