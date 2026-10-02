import Darwin
import Foundation
import os

/// Errors from preparing the copy of a Progetto for a Sessione.
nonisolated enum WorktreeError: Error, Equatable {
    /// git failed, with what it wrote on standard error.
    case git(String)
}

/// Where a Sessione works: its own worktree on its own branch, or the Progetto's folder outside git.
nonisolated struct Workspace: Codable, Equatable, Sendable {
    /// The folder `claude` runs in.
    var folder: URL
    /// The Sessione's branch; `nil` outside git.
    var branch: String?
    /// The commit the branch started from, which the revisione compares with; `nil` from a repo without commits,
    /// on the checkout, or in Sessioni saved before it was kept.
    var base: String?
    /// The branch of the checkout the Sessione started from, which Apri PR targets; `nil` from a detached checkout,
    /// outside git, or in Sessioni saved before it was kept.
    var baseBranch: String?
}

/// Makes the isolated copy of a Progetto for a new Sessione: `git worktree add` on a new branch from the
/// active one, then a copy-on-write clone of the files git ignores, so dependencies are ready at once.
nonisolated struct WorktreeManager: Sendable {
    /// The folder that holds the worktrees, one subfolder per Progetto.
    var root: URL
    /// Runs git.
    var runner = ProcessRunner.live
    /// Decides whether the Progetto's setup script may run: only in a trusted Progetto, like its hooks.
    var trustGate = TrustGate()
    /// How long the setup script may run before it is stopped.
    var setupTimeout = Duration.seconds(120)

    /// The Progetto's setup script, run with `/bin/sh` in each new worktree.
    static let setupScript = ".bubo/setup"

    /// Build caches that are never cloned, on top of `.worktreeignore`.
    static let excludedByDefault = [".build/", "build/", "DerivedData/", "dist/", ".next/", ".turbo/", ".cache/",
                                    ".parcel-cache/", "target/", ".gradle/", "__pycache__/", ".claude/worktrees/"]

    private static let git = URL(filePath: "/usr/bin/git")

    /// The worktrees of Bubo, in its Application Support folder: on the same volume as most Progetti, so
    /// `clonefile` works.
    static func makeDefault() throws -> WorktreeManager {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return WorktreeManager(root: support.appending(path: "Bubo/Worktrees", directoryHint: .isDirectory))
    }

    /// Prepares the copy of `project` for a Sessione on `branch`, or on `branch-2`, `branch-3`… if it is taken.
    ///
    /// Outside git the Sessione works in `project` itself.
    ///
    /// - Throws: `WorktreeError` when git fails.
    @concurrent func prepare(_ project: URL, branch: String) async throws -> Workspace {
        let topLevel = try await run(["rev-parse", "--show-toplevel"], in: project)
        guard topLevel.exitCode == 0 else {
            if topLevel.standardError.contains("not a git repository") { return Workspace(folder: project) }
            throw WorktreeError.git(topLevel.standardError)
        }
        let checkout = URL(filePath: topLevel.standardOutput.trimmingCharacters(in: .newlines), directoryHint: .isDirectory)
        let (name, folder) = try await availableBranch(branch, of: checkout)
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)

        let head = try await run(["rev-parse", "--verify", "--quiet", "HEAD"], in: checkout)
        let base = head.exitCode == 0 ? head.standardOutput.trimmingCharacters(in: .newlines) : nil
        let symbolic = try await run(["symbolic-ref", "--short", "-q", "HEAD"], in: checkout)
        let baseBranch = symbolic.exitCode == 0 ? symbolic.standardOutput.trimmingCharacters(in: .newlines) : nil
        try await git(base.map { ["worktree", "add", "-b", name, folder.path, $0] }
                      ?? ["worktree", "add", "--orphan", "-b", name, folder.path], in: checkout)
        try await fill(folder, from: checkout)
        return Workspace(folder: folder, branch: name, base: base, baseBranch: baseBranch)
    }

    /// Prepares again the copy of an Archiviata or Fusa Sessione that worked in `workspace`: a worktree on its branch
    /// while the branch is still there, with the same base; else a new copy as ``prepare(_:branch:)`` makes.
    ///
    /// Outside git the Sessione works in `project` itself.
    ///
    /// - Throws: `WorktreeError` when git fails.
    @concurrent func reopen(_ workspace: Workspace, of project: URL) async throws -> Workspace {
        guard let branch = workspace.branch else { return workspace }
        let topLevel = try await git(["rev-parse", "--show-toplevel"], in: project)
        let checkout = URL(filePath: topLevel.trimmingCharacters(in: .newlines), directoryHint: .isDirectory)
        let isKept = try await run(["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"], in: checkout)
            .exitCode == 0
        guard isKept else { return try await prepare(project, branch: branch) }
        let folder = worktreeFolder(of: branch, in: checkout)
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The archived worktree's record goes first, or git says the branch is checked out there.
        try await git(["worktree", "prune"], in: checkout)
        try await git(["worktree", "add", folder.path, branch], in: checkout)
        try await fill(folder, from: checkout)
        return Workspace(folder: folder, branch: branch, base: workspace.base, baseBranch: workspace.baseBranch)
    }

    /// Fills the new worktree `folder` of `checkout`: its submodules, then a clone of the files git ignores.
    private func fill(_ folder: URL, from checkout: URL) async throws {
        if FileManager.default.fileExists(atPath: folder.appending(path: ".gitmodules").path) {
            // A submodule that cannot be fetched (offline) leaves its folder empty, not the Sessione without a copy.
            do {
                try await git(["submodule", "update", "--init", "--recursive"], in: folder)
            } catch {
                Logger.sessions.error("Submodules not initialized: \(String(describing: error), privacy: .private)")
            }
        }
        for path in try await clonablePaths(in: checkout) {
            Self.clone(checkout.appending(path: path), to: folder.appending(path: path))
        }
    }

    /// The worktree folder of `branch` of `checkout`, in ``root``.
    private func worktreeFolder(of branch: String, in checkout: URL) -> URL {
        root.appending(path: checkout.lastPathComponent, directoryHint: .isDirectory)
            .appending(path: branch.replacing("/", with: "-"), directoryHint: .isDirectory)
    }

    /// The changes in the folder of `workspace` since its base, or since `HEAD` without one: commits, edits and
    /// new files, as `git diff` shows them.
    ///
    /// New files are found through a copy of the index: neither the index of the Sessione nor that of the
    /// Progetto's checkout is ever written.
    ///
    /// - Throws: `WorktreeError` when git fails, also outside a repo.
    @concurrent func changes(in workspace: Workspace) async throws -> [ChangedFile] {
        let folder = workspace.folder
        let index = try await git(["rev-parse", "--path-format=absolute", "--git-path", "index"], in: folder)
            .trimmingCharacters(in: .newlines)
        let copy = FileManager.default.temporaryDirectory.appending(path: "bubo-review-\(UUID().uuidString).index")
        defer { try? FileManager.default.removeItem(at: copy) }
        if FileManager.default.fileExists(atPath: index) { try FileManager.default.copyItem(atPath: index, toPath: copy.path) }
        let base = try await reviewBase(of: workspace)
        try await git(["add", "--intent-to-add", "--all"], in: folder, index: copy)
        let diff = try await git(["-c", "core.quotePath=false", "diff", "--no-color", "--no-ext-diff", "-M", base],
                                 in: folder, index: copy)
        return ChangedFile.files(in: diff)
    }

    /// What the revisione of `workspace` compares with: its base, or `HEAD` without one, or the empty tree.
    func reviewBase(of workspace: Workspace) async throws -> String {
        if let saved = workspace.base { return saved }
        let head = try await run(["rev-parse", "--verify", "--quiet", "HEAD"], in: workspace.folder)
        return head.exitCode == 0 ? head.standardOutput.trimmingCharacters(in: .newlines) : Self.emptyTree
    }

    /// The tree without files, to compare a repo without commits with.
    private static let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    /// Runs the Progetto's setup script in the worktree of `workspace`, if it has one, with `environment` on top
    /// of the user's login shell, disclaimed (ADR 0005).
    ///
    /// Stopping it at the timeout ends the script, not what it left running in the background.
    ///
    /// - Returns: Why the script did not complete, with the last lines it wrote; `nil` when it did or there is none.
    @concurrent func runSetup(in workspace: Workspace, environment: [String: String]) async -> String? {
        guard workspace.branch != nil,
              FileManager.default.fileExists(atPath: workspace.folder.appending(path: Self.setupScript).path)
        else { return nil }
        guard trustGate.isTrusted(workspace.folder) else {
            return String(localized: "Script di setup non eseguito: il Progetto non è fidato.")
        }
        let log = FileManager.default.temporaryDirectory.appending(path: "bubo-setup-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        // The output goes to a file: a pipe would stay open as long as anything the script left running.
        let command = "cd \(Self.quoted(workspace.folder.path)) && exec /bin/sh \(Self.setupScript) >\(Self.quoted(log.path)) 2>&1"
        var shellEnvironment = ProcessInfo.processInfo.environment.filter { ChildEnvironment.copied.contains($0.key) }
        shellEnvironment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        shellEnvironment.merge(environment) { $1 }
        let shell = URL(filePath: shellEnvironment["SHELL"] ?? "/bin/zsh")
        let runner = ProcessRunner.disclaimed(environment: shellEnvironment)
        let exitCode = try? await withThrowingTaskGroup { group in
            group.addTask { try await runner.run(shell, ["-l", "-i", "-c", command]).exitCode }
            group.addTask {
                try await Task.sleep(for: setupTimeout)
                throw CancellationError()
            }
            defer { group.cancelAll() }
            return try await group.next()
        }
        guard exitCode != 0 else { return nil }
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        let reason = if let exitCode {
            String(localized: "Lo script di setup è uscito con codice \(exitCode).")
        } else {
            String(localized: "Lo script di setup non è finito in tempo ed è stato fermato.")
        }
        return ([reason] + output.split(whereSeparator: \.isNewline).suffix(3).map(String.init)).joined(separator: "\n")
    }

    /// What deleting the Sessione of `workspace` in `project` would lose: the files changed in its worktree and
    /// the commits of its branch that no other branch has. Empty outside git, or when git cannot tell.
    @concurrent func lostChanges(in workspace: Workspace, of project: URL) async -> [String] {
        guard let branch = workspace.branch else { return [] }
        var lost: [String] = []
        if let status = try? await git(["status", "--porcelain", "--untracked-files=all"], in: workspace.folder) {
            lost += status.split(whereSeparator: \.isNewline).map { String($0.dropFirst(3)) }
        }
        if let log = try? await git(["log", "--format=%s", "refs/heads/\(branch)", "--not", "--exclude=\(branch)",
                                     "--branches", "--remotes"], in: project) {
            lost += log.split(whereSeparator: \.isNewline).map(String.init)
        }
        return lost
    }

    /// Removes the worktree of `workspace` from `project`, and its branch when `deletingBranch`.
    ///
    /// Only a folder inside `root` is ever removed, never what its symbolic links point to. When the Progetto
    /// was moved or deleted, the folder goes anyway.
    @concurrent func remove(_ workspace: Workspace, of project: URL, deletingBranch: Bool) async {
        guard let branch = workspace.branch else { return }
        let folder = workspace.folder
        if !FileManager.default.fileExists(atPath: folder.path) {
            // Already gone, as after Archivia: nothing to remove but git's record of it.
        } else if !isInsideRoot(folder) {
            Logger.sessions.error("Worktree outside the root not removed")
        } else if (try? await git(["worktree", "remove", "--force", folder.path], in: project)) == nil {
            // git cannot help when the Progetto is gone. FileManager removes a symbolic link, not what it points to.
            do {
                try FileManager.default.removeItem(at: folder)
            } catch {
                Logger.sessions.error("Worktree not removed: \(String(describing: error), privacy: .private)")
            }
        }
        _ = try? await git(["worktree", "prune"], in: project)
        if deletingBranch { _ = try? await git(["branch", "-D", branch], in: project) }
    }

    /// Whether `folder` is a real folder inside `root`, not a symbolic link that leads elsewhere.
    private func isInsideRoot(_ folder: URL) -> Bool {
        let root = TrustGate.realPath(root.path).trimmingSuffix("/") + "/"
        return TrustGate.realPath(folder.path).hasPrefix(root)
    }

    /// `text` in single quotes for any shell.
    private static func quoted(_ text: String) -> String {
        "'\(text.replacing("'", with: #"'\''"#))'"
    }

    /// The ignored paths to clone into a new worktree, relative to `checkout`.
    private func clonablePaths(in checkout: URL) async throws -> [String] {
        let list = ["ls-files", "-z", "--others", "--ignored", "--directory", "--no-empty-directory"]
        let ignored = try await git(list + ["--exclude-standard"], in: checkout)
        let include = checkout.appending(path: ".worktreeinclude")
        let included = FileManager.default.fileExists(atPath: include.path)
            ? try await git(list + ["--exclude-from=\(include.path)"], in: checkout) : nil
        let ignore = checkout.appending(path: ".worktreeignore")
        var exclusions = Self.excludedByDefault.map { "--exclude=\($0)" }
        if FileManager.default.fileExists(atPath: ignore.path) { exclusions.append("--exclude-from=\(ignore.path)") }
        let excluded = try await git(list + exclusions, in: checkout)
        return Self.clonablePaths(ignored: Self.paths(ignored), included: included.map(Self.paths),
                                  excluded: Self.paths(excluded))
    }

    /// The paths of `ignored` to clone: only those also matched by `.worktreeinclude` when there is one,
    /// never those matched by an exclusion. A folder path ends with `/` and covers everything inside it.
    static func clonablePaths(ignored: [String], included: [String]?, excluded: [String]) -> [String] {
        var paths = ignored
        if let included {
            paths = included.filter { path in ignored.contains { covers($0, path) } }
                + ignored.filter { path in included.contains { covers($0, path) } }
        }
        let unique = Set(paths)
        return unique
            .filter { path in !unique.contains { $0 != path && covers($0, path) } }
            .filter { path in !excluded.contains { covers($0, path) } }
            .sorted()
    }

    /// Whether `path` is `folder` or inside it.
    private static func covers(_ folder: String, _ path: String) -> Bool {
        folder == path || (folder.hasSuffix("/") && path.hasPrefix(folder))
    }

    private static func paths(_ output: String) -> [String] {
        output.split(separator: "\0").map(String.init)
    }

    /// The first free name among `branch`, `branch-2`, `branch-3`…, with its worktree folder.
    private func availableBranch(_ branch: String, of checkout: URL) async throws -> (String, URL) {
        var candidate = branch
        for number in 2... {
            let folder = worktreeFolder(of: candidate, in: checkout)
            let isTaken = try await run(["show-ref", "--verify", "--quiet", "refs/heads/\(candidate)"], in: checkout)
                .exitCode == 0
            if !isTaken && !FileManager.default.fileExists(atPath: folder.path) { return (candidate, folder) }
            candidate = "\(branch)-\(number)"
        }
        preconditionFailure("Unreachable: the sequence never ends")
    }

    /// Clones `source` onto `destination` with one `clonefile`, falling back to a copy on another volume.
    private static func clone(_ source: URL, to destination: URL) {
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let from = source.path(percentEncoded: false).trimmingSuffix("/")
        let to = destination.path(percentEncoded: false).trimmingSuffix("/")
        guard clonefile(from, to, UInt32(CLONE_NOFOLLOW)) != 0 else { return }
        let code = errno
        guard code == EXDEV || code == ENOTSUP else {
            Logger.sessions.error("Clone failed, errno \(code)")
            return
        }
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_CLONE | COPYFILE_NOFOLLOW)
        if copyfile(from, to, nil, flags) != 0 { Logger.sessions.error("Copy failed, errno \(errno)") }
    }

    /// Runs git in `folder`, on the index file `index` instead of the folder's own when given.
    @discardableResult
    func git(_ arguments: [String], in folder: URL, index: URL? = nil) async throws -> String {
        let output = try await run(arguments, in: folder, index: index)
        guard output.exitCode == 0 else { throw WorktreeError.git(output.standardError) }
        return output.standardOutput
    }

    /// Runs git in `folder` like `git(_:in:index:)`, leaving the exit code to the caller.
    func run(_ arguments: [String], in folder: URL, index: URL? = nil) async throws -> ProcessOutput {
        guard let index else { return try await runner.run(Self.git, ["-C", folder.path] + arguments) }
        return try await runner.run(URL(filePath: "/usr/bin/env"),
                                    ["GIT_INDEX_FILE=\(index.path)", Self.git.path, "-C", folder.path] + arguments)
    }
}

private extension String {
    nonisolated func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) && count > 1 ? String(dropLast(suffix.count)) : self
    }
}

extension Logger {
    nonisolated static let sessions = Logger(subsystem: "com.mgiuditta.bubo", category: "sessions")
}
