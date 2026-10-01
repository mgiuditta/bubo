import Foundation
import Testing
@testable import Bubo

/// `WorktreeManager` on fake repos made with the real git in a temporary folder.
struct WorktreeManagerTests {
    let base: URL
    let manager: WorktreeManager

    init() throws {
        base = URL(filePath: TrustGate.realPath(FileManager.default.temporaryDirectory.path))
            .appending(path: "WorktreeManagerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        manager = WorktreeManager(root: base.appending(path: "Worktrees", directoryHint: .isDirectory))
    }

    /// A repo at `name` with one commit of `files` (path: contents), or none when `files` is empty.
    func makeRepo(_ name: String, files: [String: String] = [:]) throws -> URL {
        let repo = base.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main", in: repo)
        guard !files.isEmpty else { return repo }
        try write(files, in: repo)
        try git("add", "-A", in: repo)
        try git("commit", "-q", "-m", "Primo", in: repo)
        return repo
    }

    func write(_ files: [String: String], in folder: URL) throws {
        for (path, contents) in files {
            let file = folder.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: file)
        }
    }

    func exists(_ path: String, in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: path).path)
    }

    @discardableResult
    func git(_ arguments: String..., in folder: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", folder.path] + arguments
        process.environment = ["GIT_AUTHOR_NAME": "Bubo", "GIT_AUTHOR_EMAIL": "bubo@example.com",
                               "GIT_COMMITTER_NAME": "Bubo", "GIT_COMMITTER_EMAIL": "bubo@example.com",
                               "HOME": base.path, "PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"]
        let output = Pipe()
        process.standardOutput = output
        let error = Pipe()
        process.standardError = error
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "git \(arguments.joined(separator: " ")): \(message)")
        return String(decoding: data, as: UTF8.self)
    }

    @Test func aWorktreeGetsTheTrackedFilesAndTheIgnoredOnesButNotTheBuildCaches() async throws {
        let repo = try makeRepo("repo", files: ["README.md": "ciao", ".gitignore": "node_modules/\n.env\n.build/\n"])
        try write(["node_modules/left-pad/index.js": "pad", ".env": "TOKEN=1", ".build/cache": "x"], in: repo)

        let workspace = try await manager.prepare(repo, branch: "bubo/prova")

        #expect(workspace.branch == "bubo/prova")
        #expect(workspace.folder.path.hasPrefix(manager.root.path))
        #expect(try git("branch", "--show-current", in: workspace.folder) == "bubo/prova\n")
        #expect(exists("README.md", in: workspace.folder))
        #expect(exists("node_modules/left-pad/index.js", in: workspace.folder))
        #expect(exists(".env", in: workspace.folder))
        #expect(!exists(".build", in: workspace.folder))
    }

    @Test func aClonedFileIsACopy() async throws {
        let repo = try makeRepo("repo", files: [".gitignore": ".env\n"])
        try write([".env": "TOKEN=1"], in: repo)

        let workspace = try await manager.prepare(repo, branch: "bubo/prova")
        try write([".env": "TOKEN=2"], in: workspace.folder)

        #expect(try String(contentsOf: repo.appending(path: ".env"), encoding: .utf8) == "TOKEN=1")
    }

    @Test func worktreeIncludeLimitsTheClonedFiles() async throws {
        let repo = try makeRepo("repo", files: [".gitignore": "node_modules/\n.env\n", ".worktreeinclude": ".env\n"])
        try write(["node_modules/a.js": "a", ".env": "TOKEN=1"], in: repo)

        let workspace = try await manager.prepare(repo, branch: "bubo/prova")

        #expect(exists(".env", in: workspace.folder))
        #expect(!exists("node_modules", in: workspace.folder))
    }

    @Test func worktreeIgnoreExcludesFiles() async throws {
        let repo = try makeRepo("repo", files: [".gitignore": "node_modules/\n.env\n", ".worktreeignore": "node_modules/\n"])
        try write(["node_modules/a.js": "a", ".env": "TOKEN=1"], in: repo)

        let workspace = try await manager.prepare(repo, branch: "bubo/prova")

        #expect(exists(".env", in: workspace.folder))
        #expect(!exists("node_modules", in: workspace.folder))
    }

    @Test func aRepoWithoutCommitsGetsAnOrphanBranch() async throws {
        let repo = try makeRepo("vuoto")
        try write([".gitignore": ".env\n", ".env": "TOKEN=1"], in: repo)

        let workspace = try await manager.prepare(repo, branch: "bubo/prova")

        #expect(workspace.branch == "bubo/prova")
        #expect(try git("branch", "--show-current", in: workspace.folder) == "bubo/prova\n")
        #expect(exists(".env", in: workspace.folder))
    }

    @Test func aFolderOutsideGitIsUsedAsItIs() async throws {
        let folder = base.appending(path: "appunti", directoryHint: .isDirectory)
        try write(["nota.md": "ciao"], in: folder)

        let workspace = try await manager.prepare(folder, branch: "bubo/prova")

        #expect(workspace == Workspace(folder: folder))
        #expect(!FileManager.default.fileExists(atPath: manager.root.path))
    }

    @Test func aTakenBranchGetsTheNextFreeName() async throws {
        let repo = try makeRepo("repo", files: ["README.md": "ciao"])
        try git("branch", "bubo/prova", in: repo)

        let first = try await manager.prepare(repo, branch: "bubo/prova")
        let second = try await manager.prepare(repo, branch: "bubo/prova")

        #expect(first.branch == "bubo/prova-2")
        #expect(second.branch == "bubo/prova-3")
        #expect(first.folder != second.folder)
    }

    @Test func submodulesAreInitialized() async throws {
        let library = try makeRepo("libreria", files: ["lib.swift": "let x = 1"])
        let repo = try makeRepo("repo", files: ["README.md": "ciao"])
        // Fake repos live on disk, so git must allow the file transport for submodules.
        try git("-c", "protocol.file.allow=always", "submodule", "add", "-q", library.path, "libreria", in: repo)
        try git("commit", "-q", "-m", "Libreria", in: repo)
        var manager = manager
        manager.runner = ProcessRunner { git, arguments in
            try await ProcessRunner.live.run(git, ["-c", "protocol.file.allow=always"] + arguments)
        }

        let workspace = try await manager.prepare(repo, branch: "bubo/prova")

        #expect(exists("libreria/lib.swift", in: workspace.folder))
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/git-lfs")
                   || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/git-lfs"), "git-lfs is not installed"))
    func lfsFilesAreCheckedOutWithTheirContents() async throws {
        let repo = try makeRepo("repo")
        try git("lfs", "install", "--local", in: repo)
        try git("lfs", "track", "*.bin", in: repo)
        try write(["dati.bin": "contenuto vero"], in: repo)
        try git("add", "-A", in: repo)
        try git("commit", "-q", "-m", "LFS", in: repo)

        let workspace = try await manager.prepare(repo, branch: "bubo/prova")

        #expect(try String(contentsOf: workspace.folder.appending(path: "dati.bin"), encoding: .utf8) == "contenuto vero")
    }

    @Test func clonablePathsFollowIncludeAndExclusions() {
        let ignored = ["node_modules/", ".env", ".env.local", "tmp/"]
        #expect(WorktreeManager.clonablePaths(ignored: ignored, included: nil, excluded: ["tmp/"])
                == [".env", ".env.local", "node_modules/"])
        #expect(WorktreeManager.clonablePaths(ignored: ignored, included: [".env", "node_modules/a/"], excluded: [])
                == [".env", "node_modules/a/"])
        #expect(WorktreeManager.clonablePaths(ignored: ["node_modules/a/"], included: ["node_modules/"], excluded: [])
                == ["node_modules/a/"])
        #expect(WorktreeManager.clonablePaths(ignored: ignored, included: nil, excluded: ["node_modules/x/"])
                .contains("node_modules/"))
    }

    /// The spec's "Sessione pronta in < 2 s con 1 GB di dipendenze": 80,000 files, 1 GB, in `node_modules`.
    ///
    /// Slow to set up, so it runs only on request: `TEST_RUNNER_BUBO_MEASURE_WORKTREE=1 xcodebuild … test`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BUBO_MEASURE_WORKTREE"] != nil))
    func aSessionWithOneGigabyteOfDependenciesIsReadyInUnderTwoSeconds() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let repo = try makeRepo("grande", files: [".gitignore": "node_modules/\n", "README.md": "ciao"])
        let contents = Data(repeating: 0x61, count: 13_422)
        for package in 0..<800 {
            let folder = repo.appending(path: "node_modules/pacchetto-\(package)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in 0..<100 { try contents.write(to: folder.appending(path: "file-\(file).js")) }
        }

        let clock = ContinuousClock()
        let start = clock.now
        let workspace = try await manager.prepare(repo, branch: "bubo/grande")
        let elapsed = clock.now - start

        print("WorktreeManager: 1 GB, 80000 file, pronta in \(elapsed)")
        #expect(exists("node_modules/pacchetto-799/file-99.js", in: workspace.folder))
        #expect(elapsed < .seconds(2))
    }
}
