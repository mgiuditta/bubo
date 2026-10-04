import Foundation

/// Conflicts resolved by the agent: the branch of the Progetto's checkout comes into the Sessione's worktree, where
/// the agent resolves them; the checkout is never touched. Its new blocchi go back to the revisione before Fondi.
nonisolated extension WorktreeManager {
    /// Brings the branch of the checkout of `project` into the branch of `workspace`, in its worktree only: the
    /// worktree's files, also those not committed, go in a commit first, then `git merge` leaves the conflicts
    /// in the files for the agent.
    ///
    /// - Returns: The merge in progress, with its conflicts: none when it merged cleanly.
    /// - Throws: `MergeError.detachedHead` when the checkout is not on a branch; `WorktreeError` when git fails.
    ///   The worktree is as it was then.
    @concurrent func bringIn(_ project: URL, into workspace: Workspace) async throws -> ConflictResolution {
        let plan = try await plan(workspace, into: project, message: "Bubo: modifiche della Sessione")
        guard let tip = plan.tip else { throw MergeError.nothingToMerge }
        let folder = workspace.folder
        let branch = String(plan.branch.dropFirst("refs/heads/".count))
        var resolution = ConflictResolution(branch: branch, incoming: plan.head, previous: tip, snapshot: plan.work,
                                            conflicts: [])
        do {
            try await git(["reset", "-q", plan.work], in: folder)
            let merged = try await run(["merge", "--no-ff", "--no-commit", "--no-verify", "-m",
                                        "Bubo: porta dentro \(branch)", plan.head], in: folder)
            guard merged.exitCode == 0 || merged.exitCode == 1 else { throw WorktreeError.git(merged.standardError) }
            resolution.conflicts = Self.fields(try await git(["-c", "core.quotePath=false", "diff", "--name-only",
                                                              "--diff-filter=U", "-z"], in: folder))
        } catch {
            try? await restore(resolution, in: workspace)
            throw error
        }
        return resolution
    }

    /// Ends the merge of `resolution` in the worktree of `workspace` with a commit, once the agent took the
    /// conflict markers out of every file.
    ///
    /// - Throws: `MergeError.unresolved` when files still have markers, or the merge is no longer there;
    ///   `WorktreeError` when git fails.
    @concurrent func conclude(_ resolution: ConflictResolution, in workspace: Workspace) async throws {
        let folder = workspace.folder
        var marked: [String] = []
        for path in resolution.conflicts {
            guard let data = await shell.contents(ofFile: folder.appending(path: path).path) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            if text.split(whereSeparator: \.isNewline).contains(where: { $0.hasPrefix("<<<<<<<") || $0.hasPrefix(">>>>>>>") }) {
                marked.append(path)
            }
        }
        guard marked.isEmpty else { throw MergeError.unresolved(marked) }
        try await git(["add", "--all"], in: folder)
        if try await run(["rev-parse", "-q", "--verify", "MERGE_HEAD"], in: folder).exitCode == 0 {
            try await git(["commit", "-q", "--no-verify", "--no-edit"], in: folder)
        }
        guard try await run(["merge-base", "--is-ancestor", resolution.incoming, "HEAD"], in: folder).exitCode == 0
        else { throw MergeError.unresolved(resolution.conflicts) }
    }

    /// Puts the worktree of `workspace` back as it was before `resolution`: its branch and every file, also
    /// those not committed; what was staged is no longer.
    ///
    /// - Throws: `WorktreeError` when git fails.
    @concurrent func restore(_ resolution: ConflictResolution, in workspace: Workspace) async throws {
        let folder = workspace.folder
        try await git(["reset", "-q", "--hard", resolution.snapshot], in: folder)
        // The snapshot has every file git does not ignore: what is left out came after it.
        try await git(["clean", "-q", "-f", "-d"], in: folder)
        try await git(["reset", "-q", resolution.previous], in: folder)
    }
}
