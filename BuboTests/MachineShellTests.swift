import Foundation
import Testing
@testable import Bubo

/// `LocalShell` and `SSHShell` with the same suite. `SSHShell` runs on a fake OpenSSH that hands the line meant
/// for the host to the Mac's `/bin/sh`: no test connects, yet the quoting is checked end to end.
struct MachineShellTests {
    /// The Macchina of the fake.
    nonisolated static let machine = Machine(alias: "officina", user: "matteo", hostname: "officina.lan")

    /// An `SSHShell` whose `ssh` runs the host's line here, recording the arguments in `recorder` when given.
    nonisolated static func fakeSSHShell(recording recorder: ArgumentsRecorder? = nil) -> SSHShell {
        var shell = SSHShell(machine: machine, controlFolder: URL(filePath: "/tmp/bubo-test"))
        shell.openSSH = { arguments, input in
            await recorder?.record(arguments)
            guard let line = arguments.last else { throw MachineShellError.failed("ssh without a command") }
            let runner = input.map { ProcessRunner.live(environment: nil, input: $0) } ?? .live
            return try await runner.run(URL(filePath: "/bin/sh"), ["-c", line])
        }
        return shell
    }

    /// Both shells, for the suite they share.
    nonisolated static let shells: [any MachineShell] = [LocalShell(), fakeSSHShell()]

    @Test(arguments: [
        "semplice", "con spazi", "l'apice", #"doppi "apici""#, "$HOME e `date`", "a\\b", "città ✓ 🦉", "-n", "",
        "riga\nnuova", "*", ";rm -rf /",
    ])
    func sshRunsEveryWordAsItIs(word: String) async throws {
        let output = try await Self.fakeSSHShell().run(["printf", "%s", word])

        #expect(output.exitCode == 0)
        #expect(output.standardOutput == word)
    }

    @Test func sshPassesTheEnvironmentAsItIs() async throws {
        let value = "spazi, 'apici', $PATH e città"

        let output = try await Self.fakeSSHShell().run(["printenv", "BUBO_PROVA"], environment: ["BUBO_PROVA": value])

        #expect(output.standardOutput == value + "\n")
    }

    @Test func sshRunsInTheBackgroundOnAKnownHostWithoutQuestions() async throws {
        let recorder = ArgumentsRecorder()

        _ = try await Self.fakeSSHShell(recording: recorder).run(["true"])

        let arguments = try #require(await recorder.calls.first)
        #expect(arguments.contains("BatchMode=yes"))
        #expect(arguments.contains("StrictHostKeyChecking=yes"))
        #expect(!arguments.contains { $0.hasPrefix("StrictHostKeyChecking=no") })
        #expect(Array(arguments.suffix(3).dropLast()) == ["--", "officina"])
    }

    @Test func aConnectionThatFailsIsUnreachable() async throws {
        var shell = Self.fakeSSHShell()
        shell.openSSH = { _, _ in ProcessOutput(exitCode: 255, standardOutput: "", standardError: "Connection refused") }

        await #expect(throws: MachineShellError.unreachable("Connection refused")) {
            try await shell.run(["true"])
        }
    }

    @Test(arguments: shells)
    func readsFilesAndInput(shell: any MachineShell) async throws {
        let contents = try await shell.withTemporaryFolder { folder in
            let file = folder + "/nota con spazi.txt"
            #expect(await !shell.fileExists(atPath: file))
            let written = try await shell.run(["sh", "-c", #"cat > "$1""#, "sh", file], environment: [:],
                                              input: Data("ciao, città\n".utf8))
            #expect(written.exitCode == 0)
            #expect(await shell.fileExists(atPath: file))
            return await shell.contents(ofFile: file)
        }

        #expect(contents == Data("ciao, città\n".utf8))
    }

    @Test(arguments: shells)
    func theTemporaryFolderIsRemovedAfterwards(shell: any MachineShell) async throws {
        let folder = try await shell.withTemporaryFolder { $0 }

        #expect(await !shell.fileExists(atPath: folder))
    }

    @Test(arguments: shells)
    func aMissingFileHasNoContents(shell: any MachineShell) async {
        #expect(await shell.contents(ofFile: "/non/esiste/bubo") == nil)
    }
}

/// The arguments of each fake `ssh`.
actor ArgumentsRecorder {
    private(set) var calls: [[String]] = []

    func record(_ arguments: [String]) {
        calls.append(arguments)
    }
}

/// The revisione and Fondi per blocco through each shell, on fake repos made with the real git.
extension WorktreeManagerTests {
    /// Twenty lines, with the first and the last changed when `changed`: two blocchi far apart.
    static func lines(changed: Bool) -> String {
        (1...20).map { line in changed && (line == 1 || line == 20) ? "nuova \(line)" : "riga \(line)" }
            .joined(separator: "\n") + "\n"
    }

    @Test(arguments: MachineShellTests.shells)
    func reviewAndFondiPerBloccoGoThroughTheShell(shell: any MachineShell) async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": Self.lines(changed: false)])
        try write(["a.txt": Self.lines(changed: true), "nuovo.txt": "nuovo\n"], in: workspace.folder)
        var remote = manager
        remote.shell = shell

        let files = try await remote.changes(in: workspace)
        let changed = try #require(files.first { $0.path == "a.txt" })
        try #require(changed.hunks.count == 2)
        let accepted = Set([changed.hunks[0].id] + files.filter { $0.path == "nuovo.txt" }.flatMap(\.hunks).map(\.id))
        let preview = try await remote.mergePreview(of: workspace, into: repo)
        _ = try await remote.merge(workspace, into: repo, message: "Prova", strategy: .squash, keepingOnly: accepted)

        #expect(preview.conflicts.isEmpty)
        #expect(Set(files.map(\.path)) == ["a.txt", "nuovo.txt"])
        let merged = try read("a.txt", in: repo)
        #expect(merged.hasPrefix("nuova 1\n"))
        #expect(merged.hasSuffix("riga 20\n"))
        #expect(try read("nuovo.txt", in: repo) == "nuovo\n")
        #expect(try read("a.txt", in: workspace.folder) == Self.lines(changed: true))
    }

    @Test(arguments: MachineShellTests.shells)
    func conflictsAreResolvedThroughTheShell(shell: any MachineShell) async throws {
        let (repo, workspace) = try await makeSession(files: ["a.txt": "a\n"])
        try write(["a.txt": "sessione\n"], in: workspace.folder)
        try write(["a.txt": "checkout\n"], in: repo)
        try git("commit", "-q", "-am", "Checkout", in: repo)
        var remote = manager
        remote.shell = shell

        let resolution = try await remote.bringIn(repo, into: workspace)
        await #expect(throws: MergeError.unresolved(["a.txt"])) {
            try await remote.conclude(resolution, in: workspace)
        }
        try write(["a.txt": "entrambi\n"], in: workspace.folder)
        try await remote.conclude(resolution, in: workspace)

        #expect(resolution.conflicts == ["a.txt"])
        #expect(try read("a.txt", in: workspace.folder) == "entrambi\n")
    }
}
