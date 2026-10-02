import Foundation
import Testing
@testable import Bubo

/// `BranchBundler` on fake repos made with the real git in a temporary folder.
struct BranchBundlerTests {
    let base: URL
    let bundler = BranchBundler()

    init() throws {
        base = URL(filePath: TrustGate.realPath(FileManager.default.temporaryDirectory.path))
            .appending(path: "BranchBundlerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    /// A repo on `main` with one pushed commit, then the Sessione's branch `bubo/stampa` with one commit, a changed
    /// file, a new file and an ignored file not committed.
    func makeSessionRepo() throws -> (repo: URL, pushed: String) {
        let repo = base.appending(path: "repo", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main", in: repo)
        try write(["README.md": "ciao\n", ".gitignore": ".env\nnode_modules/\n"], in: repo)
        try git("add", "-A", in: repo)
        try git("commit", "-q", "-m", "Primo", in: repo)
        let pushed = try git("rev-parse", "HEAD", in: repo).trimmingCharacters(in: .newlines)
        // What `git push` would leave: the remote's main branch at the pushed commit.
        try git("update-ref", "refs/remotes/origin/main", pushed, in: repo)
        try git("switch", "-q", "-c", "bubo/stampa", in: repo)
        try write(["stampa.swift": "print(1)\n"], in: repo)
        try git("add", "-A", in: repo)
        try git("commit", "-q", "-m", "Stampa", in: repo)
        try write(["README.md": "ciao, mondo\n", "nuovo.txt": "nuovo\n", ".env": "TOKEN=segreto\n",
                   "node_modules/x/index.js": "x"], in: repo)
        return (repo, pushed)
    }

    func write(_ files: [String: String], in folder: URL) throws {
        for (path, contents) in files {
            let file = folder.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: file)
        }
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

    /// What `git status`, the index and the refs say of `repo`.
    func state(of repo: URL) throws -> [String] {
        [try git("status", "--porcelain=v1", "--untracked-files=all", in: repo),
         try git("ls-files", "--stage", in: repo),
         try git("for-each-ref", in: repo),
         try git("rev-parse", "HEAD", in: repo)]
    }

    @Test func theSendersWorktreeIsTheSameBeforeAndAfter() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let (repo, _) = try makeSessionRepo()
        try git("add", "README.md", in: repo) // something staged too, which must stay staged
        let before = try state(of: repo)

        let snapshot = try await bundler.snapshot(of: repo, branch: "bubo/stampa", fallbackBase: nil)
        _ = try await bundler.bundle(snapshot, in: repo, sender: "Ada", to: base.appending(path: "ramo.bundle"))

        #expect(try state(of: repo) == before)
    }

    @Test func theBundleHasTheCommitsAndTheUncommittedChangesButNotTheIgnoredFiles() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let (repo, pushed) = try makeSessionRepo()
        let file = base.appending(path: "ramo.bundle")

        let snapshot = try await bundler.snapshot(of: repo, branch: "bubo/stampa", fallbackBase: nil)
        let ref = try #require(try await bundler.bundle(snapshot, in: repo, sender: "Ada", to: file))

        #expect(snapshot.base == pushed)
        #expect(snapshot.commitCount == 1)
        #expect(snapshot.hasUncommittedChanges)
        #expect(Set(snapshot.changedFiles) == ["README.md", "nuovo.txt", "stampa.swift"])
        #expect(snapshot.uncommittedDiff.contains("ciao, mondo"))
        #expect(!snapshot.uncommittedDiff.contains("segreto"))

        // The receiver has the pushed commit, as a clone of the remote would.
        let clone = base.appending(path: "clone", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: clone, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main", in: clone)
        try git("fetch", "-q", repo.path, "main", in: clone)
        try git("update-ref", "refs/heads/main", pushed, in: clone)
        try git("fetch", "-q", file.path, "\(ref):refs/heads/consegna/ada/stampa", in: clone)

        let files = try git("ls-tree", "-r", "--name-only", "consegna/ada/stampa", in: clone)
            .split(separator: "\n").map(String.init)
        #expect(Set(files) == [".gitignore", "README.md", "nuovo.txt", "stampa.swift"])
        #expect(try git("show", "consegna/ada/stampa:README.md", in: clone) == "ciao, mondo\n")
        let log = try git("log", "--format=%s|%ae", "\(pushed)..consegna/ada/stampa", in: clone)
        #expect(log.split(separator: "\n").count == 2)
        #expect(log.hasPrefix("Modifiche non salvate di Ada|\(BranchBundler.committerEmail)"))
    }

    @Test func aCloneWithoutTheBaseCannotFetchTheBundle() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let (repo, _) = try makeSessionRepo()
        let file = base.appending(path: "ramo.bundle")
        let snapshot = try await bundler.snapshot(of: repo, branch: "bubo/stampa", fallbackBase: nil)
        _ = try await bundler.bundle(snapshot, in: repo, sender: "Ada", to: file)

        let empty = base.appending(path: "vuoto", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try git("init", "-q", in: empty)
        let verify = Process()
        verify.executableURL = URL(filePath: "/usr/bin/git")
        verify.arguments = ["-C", empty.path, "bundle", "verify", "--quiet", file.path]
        verify.standardError = FileHandle.nullDevice
        try verify.run()
        verify.waitUntilExit()

        #expect(verify.terminationStatus != 0)
    }

    @Test func aBranchWithNothingNewHasNoBundle() async throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let repo = base.appending(path: "repo", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main", in: repo)
        try write(["README.md": "ciao\n"], in: repo)
        try git("add", "-A", in: repo)
        try git("commit", "-q", "-m", "Primo", in: repo)
        let head = try git("rev-parse", "HEAD", in: repo).trimmingCharacters(in: .newlines)
        let file = base.appending(path: "ramo.bundle")

        let snapshot = try await bundler.snapshot(of: repo, branch: "main", fallbackBase: head)

        #expect(snapshot.isEmpty)
        #expect(try await bundler.bundle(snapshot, in: repo, sender: "Ada", to: file) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
