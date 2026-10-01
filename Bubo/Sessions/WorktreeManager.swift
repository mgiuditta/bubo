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
}

/// Makes the isolated copy of a Progetto for a new Sessione: `git worktree add` on a new branch from the
/// active one, then a copy-on-write clone of the files git ignores, so dependencies are ready at once.
nonisolated struct WorktreeManager: Sendable {
    /// The folder that holds the worktrees, one subfolder per Progetto.
    var root: URL
    /// Runs git.
    var runner = ProcessRunner.live

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

        let hasCommits = try await run(["rev-parse", "--verify", "--quiet", "HEAD"], in: checkout).exitCode == 0
        try await git(hasCommits ? ["worktree", "add", "-b", name, folder.path, "HEAD"]
                                 : ["worktree", "add", "--orphan", "-b", name, folder.path], in: checkout)
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
        return Workspace(folder: folder, branch: name)
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
        let projectFolder = root.appending(path: checkout.lastPathComponent, directoryHint: .isDirectory)
        var candidate = branch
        for number in 2... {
            let folder = projectFolder.appending(path: candidate.replacing("/", with: "-"), directoryHint: .isDirectory)
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

    @discardableResult
    private func git(_ arguments: [String], in folder: URL) async throws -> String {
        let output = try await run(arguments, in: folder)
        guard output.exitCode == 0 else { throw WorktreeError.git(output.standardError) }
        return output.standardOutput
    }

    private func run(_ arguments: [String], in folder: URL) async throws -> ProcessOutput {
        try await runner.run(Self.git, ["-C", folder.path] + arguments)
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
