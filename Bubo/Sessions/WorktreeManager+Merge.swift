import Foundation

/// Fondi: brings a Sessione's work into the branch of the Progetto's checkout, and undoes it.
///
/// Conflicts are worked out with `git merge-tree`, which reads and writes neither an index nor a working tree. The
/// merge then moves only the files it changes, as `git checkout` does: unsaved changes elsewhere in the checkout
/// stay as they are, and nothing is ever stashed or pushed.
nonisolated extension WorktreeManager {
    /// What merging `workspace` into the checkout of `project` would do now, without touching either.
    ///
    /// - Throws: `MergeError.detachedHead` when the checkout is not on a branch; `WorktreeError` when git fails.
    @concurrent func mergePreview(of workspace: Workspace, into project: URL) async throws -> MergePreview {
        let plan = try await plan(workspace, into: project, message: "Bubo")
        return MergePreview(branch: String(plan.branch.dropFirst("refs/heads/".count)), conflicts: plan.conflicts,
                            dirtyFiles: plan.dirtyFiles, isEmpty: plan.changedFiles.isEmpty)
    }

    /// Merges the work of `workspace`, also what is not committed yet, into the branch of the checkout of
    /// `project` as one commit with `message`.
    ///
    /// - Parameter accepted: The blocchi to bring, by id: the others stay out, and the worktree keeps them;
    ///   `nil` brings them all.
    /// - Returns: The merge, to undo it.
    /// - Throws: `MergeError` when the merge would conflict, would change files with unsaved changes, or has
    ///   nothing to bring; `WorktreeError` when git fails. The checkout is as it was then.
    @concurrent func merge(_ workspace: Workspace, into project: URL, message: String, strategy: MergeStrategy,
                           keepingOnly accepted: Set<String>? = nil) async throws -> Merge {
        let plan = try await plan(workspace, into: project, message: message, keepingOnly: accepted)
        if let obstacle = MergePreview(branch: plan.branch, conflicts: plan.conflicts, dirtyFiles: plan.dirtyFiles,
                                       isEmpty: plan.changedFiles.isEmpty).obstacle {
            throw obstacle
        }
        let parents = strategy == .squash ? [plan.head] : [plan.head, plan.work]
        let commit = try await git(["commit-tree", plan.tree, "-m", message] + parents.flatMap { ["-p", $0] },
                                   in: plan.checkout).trimmingCharacters(in: .newlines)
        let merge = Merge(checkout: plan.checkout, branch: plan.branch, previous: plan.head, commit: commit)
        try await move(merge.branch, in: merge.checkout, from: merge.previous, to: merge.commit,
                       reason: "Bubo: fondi \(workspace.branch ?? "")")
        return merge
    }

    /// Puts the checkout of `merge` back as it was before it: its branch, and the files the merge changed.
    ///
    /// - Throws: `MergeError.moved` when the branch is no longer on the merge; `WorktreeError` when git fails,
    ///   as when those files were changed since. The checkout is as it was then.
    @concurrent func undo(_ merge: Merge) async throws {
        let head = try await run(["symbolic-ref", "-q", "HEAD"], in: merge.checkout)
        let tip = try await run(["rev-parse", "--verify", "-q", merge.branch], in: merge.checkout)
        guard head.standardOutput.trimmingCharacters(in: .newlines) == merge.branch,
              tip.standardOutput.trimmingCharacters(in: .newlines) == merge.commit
        else { throw MergeError.moved }
        try await move(merge.branch, in: merge.checkout, from: merge.commit, to: merge.previous,
                       reason: "Bubo: annulla merge")
    }

    /// Moves `branch`, checked out in `checkout`, from `old` to `new` with the index and the files that differ
    /// between them; the other files, and their unsaved changes, stay as they are.
    ///
    /// `git read-tree -m -u` refuses to overwrite unsaved changes, so it goes first; the branch moves only if
    /// still on `old`, or the files go back.
    private func move(_ branch: String, in checkout: URL, from old: String, to new: String, reason: String) async throws {
        _ = try await run(["update-index", "-q", "--refresh"], in: checkout)
        try await git(["read-tree", "-m", "-u", old, new], in: checkout)
        do {
            try await git(["update-ref", "-m", reason, branch, new, old], in: checkout)
        } catch {
            _ = try? await git(["read-tree", "-m", "-u", new, old], in: checkout)
            throw error
        }
    }

    /// What a merge needs, worked out without touching the checkout or the worktree.
    struct Plan {
        /// The repo's top folder.
        var checkout: URL
        /// The full name of the checkout's branch.
        var branch: String
        /// The commit of the checkout's branch.
        var head: String
        /// The commit of the Sessione's branch; `nil` before its first.
        var tip: String?
        /// A commit with the Sessione's work, also what is not committed yet, on top of its branch.
        var work: String
        /// The tree of the merge.
        var tree: String
        var conflicts: [String]
        /// The files the merge changes, relative to the repo.
        var changedFiles: [String]
        /// The changed files that have unsaved changes in the checkout.
        var dirtyFiles: [String]
    }

    func plan(_ workspace: Workspace, into project: URL, message: String,
                      keepingOnly accepted: Set<String>? = nil) async throws -> Plan {
        guard workspace.branch != nil else { throw MergeError.nothingToMerge }
        let checkout = URL(filePath: try await git(["rev-parse", "--show-toplevel"], in: project)
            .trimmingCharacters(in: .newlines), directoryHint: .isDirectory)
        let symbolic = try await run(["symbolic-ref", "-q", "HEAD"], in: checkout)
        guard symbolic.exitCode == 0 else { throw MergeError.detachedHead }
        let branch = symbolic.standardOutput.trimmingCharacters(in: .newlines)
        let head = try await git(["rev-parse", "--verify", "HEAD"], in: checkout).trimmingCharacters(in: .newlines)

        let folder = workspace.folder
        let workTree = try await withIndexCopy(of: folder) { copy in
            try await git(["add", "--all"], in: folder, index: copy)
            if let accepted { try await discard(blocchiOutside: accepted, of: workspace, in: copy) }
            return try await git(["write-tree"], in: folder, index: copy).trimmingCharacters(in: .newlines)
        }
        let tip = try await run(["rev-parse", "--verify", "-q", "HEAD"], in: folder)
        let tipCommit = tip.exitCode == 0 ? tip.standardOutput.trimmingCharacters(in: .newlines) : nil
        let parent = tipCommit.map { ["-p", $0] } ?? []
        let work = try await git(["commit-tree", workTree, "-m", message] + parent, in: folder)
            .trimmingCharacters(in: .newlines)

        let merged = try await run(["-c", "core.quotePath=false", "merge-tree", "--write-tree", "--name-only",
                                    "--no-messages", "-z", head, work], in: checkout)
        guard merged.exitCode == 0 || merged.exitCode == 1 else { throw WorktreeError.git(merged.standardError) }
        let fields = Self.fields(merged.standardOutput)
        guard let tree = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines), !tree.isEmpty else {
            throw WorktreeError.git(merged.standardError)
        }
        let conflicts = Array(Set(fields.dropFirst())).sorted()

        let changedFiles = Self.fields(try await git(["-c", "core.quotePath=false", "diff", "--name-only", "-z",
                                                      "--no-renames", head, tree], in: checkout))
        // Without optional locks, so that reading the checkout never holds its index from the user.
        let status = Self.fields(try await git(["--no-optional-locks", "status", "--porcelain=v1", "-z",
                                                "--untracked-files=all"], in: checkout))
        let dirty = Set(Self.paths(inStatus: status))
        return Plan(checkout: checkout, branch: branch, head: head, tip: tipCommit, work: work, tree: tree, conflicts: conflicts,
                    changedFiles: changedFiles, dirtyFiles: changedFiles.filter(dirty.contains))
    }

    /// Takes out of `index`, a copy of the worktree's index with every file in it, the blocchi of `workspace`
    /// that are not in `accepted`: a file without any accepted goes back to the revisione's base, the others
    /// lose those blocchi through `git apply --reverse`.
    private func discard(blocchiOutside accepted: Set<String>, of workspace: Workspace, in index: URL) async throws {
        let folder = workspace.folder
        let base = try await reviewBase(of: workspace)
        var patch = ""
        for file in try await changes(in: workspace) {
            let rejected = file.hunks.filter { !accepted.contains($0.id) }
            if rejected.isEmpty { continue }
            if rejected.count == file.hunks.count {
                try await git(["reset", "-q", base, "--", file.path] + (file.oldPath.map { [$0] } ?? []),
                              in: folder, index: index)
                continue
            }
            patch += "diff --git a/\(file.path) b/\(file.path)\n--- a/\(file.path)\n+++ b/\(file.path)\n"
            for hunk in rejected {
                patch += hunk.header + "\n" + hunk.lines.map { line in
                    switch line.kind {
                    case .context: " " + line.text
                    case .added: "+" + line.text
                    case .removed: "-" + line.text
                    }
                }.joined(separator: "\n") + "\n"
            }
        }
        guard !patch.isEmpty else { return }
        try await git(["apply", "--cached", "--reverse", "--recount", "-"], in: folder, index: index,
                      input: Data(patch.utf8))
    }

    /// The paths of `git status --porcelain -z`, split at NUL: both sides of a rename or a copy.
    private static func paths(inStatus fields: [String]) -> [String] {
        var paths: [String] = []
        var takesOrigin = false
        for field in fields {
            if takesOrigin {
                paths.append(field)
                takesOrigin = false
            } else {
                paths.append(String(field.dropFirst(3)))
                takesOrigin = field.first == "R" || field.first == "C"
            }
        }
        return paths
    }

    /// The non-empty fields of NUL-separated output.
    static func fields(_ output: String) -> [String] {
        output.split(separator: "\0").map(String.init).filter { !$0.trimmingCharacters(in: .newlines).isEmpty }
    }
}
