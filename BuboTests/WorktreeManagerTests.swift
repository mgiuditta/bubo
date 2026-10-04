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
        #expect(TrustGate.mainCheckout(ofWorktree: workspace.folder) == repo.path)
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
        manager.shell = LocalShell(environment: ProcessInfo.processInfo.environment.merging(
            ["GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "protocol.file.allow", "GIT_CONFIG_VALUE_0": "always"]
        ) { $1 })

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

    @Test func archivingRemovesTheWorktreeAndKeepsTheBranch() async throws {
        let repo = try makeRepo("repo", files: ["README.md": "ciao", ".gitignore": "node_modules/\n"])
        try write(["node_modules/a.js": "a"], in: repo)
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")
        try write(["nuovo.txt": "x"], in: workspace.folder)

        await manager.remove(workspace, of: repo, deletingBranch: false)

        #expect(!FileManager.default.fileExists(atPath: workspace.folder.path))
        #expect(try git("branch", "--list", "bubo/prova", in: repo).contains("bubo/prova"))
        #expect(try git("worktree", "list", "--porcelain", in: repo).components(separatedBy: "worktree ").count == 2)
        #expect(exists("node_modules/a.js", in: repo))
    }

    @Test func deletingRemovesTheWorktreeAndTheBranch() async throws {
        let repo = try makeRepo("repo", files: ["README.md": "ciao"])
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")

        await manager.remove(workspace, of: repo, deletingBranch: true)

        #expect(!FileManager.default.fileExists(atPath: workspace.folder.path))
        #expect(try git("branch", "--list", "bubo/prova", in: repo).isEmpty)
    }

    @Test func removingAWorktreeLeavesWhatItsLinksPointTo() async throws {
        let repo = try makeRepo("repo", files: ["README.md": "ciao"])
        let outside = base.appending(path: "fuori", directoryHint: .isDirectory)
        try write(["prezioso.txt": "non toccare"], in: outside)
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")
        try FileManager.default.createSymbolicLink(at: workspace.folder.appending(path: "collegamento"),
                                                   withDestinationURL: outside)

        await manager.remove(workspace, of: repo, deletingBranch: true)

        #expect(!FileManager.default.fileExists(atPath: workspace.folder.path))
        #expect(exists("prezioso.txt", in: outside))
    }

    @Test func aFolderOutsideTheRootIsNeverRemoved() async throws {
        let repo = try makeRepo("repo", files: ["README.md": "ciao"])

        await manager.remove(Workspace(folder: repo, branch: "main"), of: repo, deletingBranch: false)
        let link = manager.root.appending(path: "repo/collegamento", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo)
        await manager.remove(Workspace(folder: link, branch: "main"), of: repo, deletingBranch: false)

        #expect(exists("README.md", in: repo))
    }

    @Test func aWorktreeIsRemovedEvenWhenItsProjectIsGone() async throws {
        let repo = try makeRepo("repo", files: ["README.md": "ciao"])
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")
        try FileManager.default.removeItem(at: repo)

        await manager.remove(workspace, of: repo, deletingBranch: true)

        #expect(!FileManager.default.fileExists(atPath: workspace.folder.path))
    }

    @Test func theLostChangesAreTheChangedFilesAndTheCommitsOnlyTheBranchHas() async throws {
        let repo = try makeRepo("repo", files: ["README.md": "ciao"])
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")
        try write(["fatto.txt": "x"], in: workspace.folder)
        try git("add", "-A", in: workspace.folder)
        try git("commit", "-q", "-m", "Aggiunge fatto", in: workspace.folder)
        try write(["README.md": "cambiato", "bozza.txt": "y"], in: workspace.folder)

        let lost = await manager.lostChanges(in: workspace, of: repo)

        #expect(Set(lost) == ["README.md", "bozza.txt", "Aggiunge fatto"])
    }

    @Test func aBranchWithNothingNewLosesNothing() async throws {
        let repo = try makeRepo("repo", files: ["README.md": "ciao"])
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")

        #expect(await manager.lostChanges(in: workspace, of: repo).isEmpty)
    }

    /// `manager` with `repo` trusted, as if accepted in the CLI.
    func managerTrusting(_ repo: URL) throws -> WorktreeManager {
        let configuration = base.appending(path: "claude.json")
        let projects = [TrustGate.root(of: repo): ["hasTrustDialogAccepted": true]]
        try JSONSerialization.data(withJSONObject: ["projects": projects]).write(to: configuration)
        var trusting = manager
        trusting.trustGate = TrustGate(configuration: configuration)
        return trusting
    }

    @Test func theSetupScriptRunsInTheWorktreeWithTheSessionsPorts() async throws {
        let repo = try makeRepo("repo", files: [WorktreeManager.setupScript: "pwd -P > fatto\necho $PORT $BUBO_PORT >> fatto\n"])
        let manager = try managerTrusting(repo)
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")

        let failure = await manager.runSetup(in: workspace, environment: ["PORT": "40010", "BUBO_PORT": "40010"])

        #expect(failure == nil)
        let done = try String(contentsOf: workspace.folder.appending(path: "fatto"), encoding: .utf8)
        #expect(done == "\(TrustGate.realPath(workspace.folder.path))\n40010 40010\n")
    }

    @Test func aFailingSetupScriptSaysWhy() async throws {
        let repo = try makeRepo("repo", files: [WorktreeManager.setupScript: "echo installo\necho 'npm: manca' >&2\nexit 3\n"])
        let manager = try managerTrusting(repo)
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")

        let failure = try #require(await manager.runSetup(in: workspace, environment: [:]))

        #expect(failure.contains("3"))
        #expect(failure.hasSuffix("installo\nnpm: manca"))
    }

    @Test func aSetupScriptThatTakesTooLongIsStopped() async throws {
        let repo = try makeRepo("repo", files: [WorktreeManager.setupScript: "sleep 30\n"])
        var manager = try managerTrusting(repo)
        manager.setupTimeout = .seconds(1)
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")

        let start = ContinuousClock.now
        let failure = await manager.runSetup(in: workspace, environment: [:])

        #expect(failure != nil)
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func theSetupScriptOfAnUntrustedProjectDoesNotRun() async throws {
        let repo = try makeRepo("repo", files: [WorktreeManager.setupScript: "touch fatto\n"])
        var manager = manager
        manager.trustGate = TrustGate(configuration: base.appending(path: "nessuno.json"))
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")

        let failure = await manager.runSetup(in: workspace, environment: [:])

        #expect(failure != nil)
        #expect(!exists("fatto", in: workspace.folder))
    }

    @Test func aProjectWithoutASetupScriptNeedsNothing() async throws {
        let repo = try makeRepo("repo", files: ["README.md": "ciao"])
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")
        #expect(await manager.runSetup(in: workspace, environment: [:]) == nil)
    }

    @Test func theChangesAreTheCommitsTheEditsAndTheNewFilesSinceTheBase() async throws {
        let repo = try makeRepo("repo", files: ["a.txt": "uno\ndue\ntre\n", "via.txt": "x\n", ".gitignore": "node_modules/\n"])
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")
        try write(["a.txt": "uno\nDUE\ntre\n"], in: workspace.folder)
        try git("commit", "-q", "-am", "Della Sessione", in: workspace.folder)
        try write(["nuovo.txt": "ciao\n", "node_modules/x.js": "ignorato"], in: workspace.folder)
        try FileManager.default.removeItem(at: workspace.folder.appending(path: "via.txt"))
        let status = try git("status", "--porcelain", in: workspace.folder)

        let files = try await manager.changes(in: workspace)

        #expect(workspace.base != nil)
        #expect(files.map(\.path) == ["a.txt", "nuovo.txt", "via.txt"])
        #expect(files.map { $0.hunks.map(\.added) } == [[1], [1], [0]])
        #expect(files.map { $0.hunks.map(\.removed) } == [[1], [0], [1]])
        // Neither the Sessione's index nor the checkout's is written.
        #expect(try git("status", "--porcelain", in: workspace.folder) == status)
        #expect(try git("status", "--porcelain", in: repo).isEmpty)
    }

    @Test func aRepoWithoutCommitsShowsItsFilesAsNew() async throws {
        let repo = try makeRepo("vuoto")
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")
        try write(["primo.txt": "ciao\n"], in: workspace.folder)

        let files = try await manager.changes(in: workspace)

        #expect(workspace.base == nil)
        #expect(files.map(\.path) == ["primo.txt"])
    }

    /// The spec's "diff aggiornato < 300 ms" after a write in a file of 50,000 lines, and the time to read a diff of
    /// 50,000 changed lines into rows, before the first frame.
    ///
    /// Runs only on request: `TEST_RUNNER_BUBO_MEASURE_REVIEW=1 xcodebuild … test`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BUBO_MEASURE_REVIEW"] != nil))
    func aWriteInALargeFileIsReadInUnderThreeHundredMilliseconds() async throws {
        let original = (0..<50_000).map { "riga \($0)" }
        let repo = try makeRepo("grande", files: ["grande.txt": original.joined(separator: "\n")])
        let workspace = try await manager.prepare(repo, branch: "bubo/prova")
        var edited = original
        for index in stride(from: 0, to: edited.count, by: 5_000) { edited[index] = "cambiata \(index)" }
        try write(["grande.txt": edited.joined(separator: "\n")], in: workspace.folder)
        let clock = ContinuousClock()

        let smallEdit = try await clock.measure { _ = try await manager.changes(in: workspace) }
        try write(["grande.txt": original.map { "nuova \($0)" }.joined(separator: "\n")], in: workspace.folder)
        var files: [ChangedFile] = []
        let large = try await clock.measure { files = try await manager.changes(in: workspace) }
        var review = Review()
        let rows = clock.measure { review = Review(files: files) }

        print("Revisione: 10 blocchi in \(smallEdit); 100.000 righe di diff in \(large), righe della vista in \(rows)")
        #expect(review.rows.count > 100_000)
        #expect(smallEdit < .milliseconds(300))
    }

    @Test func aFolderOutsideGitHasNoChangesToShow() async throws {
        let folder = base.appending(path: "senza-git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await #expect(throws: WorktreeError.self) { try await manager.changes(in: Workspace(folder: folder)) }
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

    @Test func aNewSessionOnAnIssueWhoseBranchIsTakenGetsASuffix() async throws {
        let repo = try makeRepo("repo", files: ["README.md": "ciao"])
        let branch = IssueLink.branch(forIssue: 42, titled: "Fix login")
        try git("branch", branch, in: repo)

        let workspace = try await manager.prepare(repo, branch: branch)

        #expect(workspace.branch == "bubo/42-fix-login-2")
    }

    @Test func reopeningAnArchivedSessionReusesItsBranchAndItsBase() async throws {
        let repo = try makeRepo("repo", files: ["README.md": "ciao"])
        let archived = try await manager.prepare(repo, branch: "bubo/42-fix-login")
        try write(["nuovo.txt": "lavoro"], in: archived.folder)
        try git("add", "-A", in: archived.folder)
        try git("commit", "-q", "-m", "Lavoro", in: archived.folder)
        await manager.remove(archived, of: repo, deletingBranch: false)

        let reopened = try await manager.reopen(archived, of: repo)

        #expect(reopened.branch == "bubo/42-fix-login")
        #expect(reopened.base == archived.base)
        #expect(exists("nuovo.txt", in: reopened.folder))
        #expect(try git("branch", "--show-current", in: reopened.folder) == "bubo/42-fix-login\n")
    }

    @Test func reopeningASessionWhoseBranchFondiDeletedPreparesANewOne() async throws {
        let repo = try makeRepo("repo", files: ["README.md": "ciao"])
        let merged = try await manager.prepare(repo, branch: "bubo/42-fix-login")
        await manager.remove(merged, of: repo, deletingBranch: true)

        let reopened = try await manager.reopen(merged, of: repo)

        #expect(reopened.branch == "bubo/42-fix-login")
        #expect(exists("README.md", in: reopened.folder))
    }
}
