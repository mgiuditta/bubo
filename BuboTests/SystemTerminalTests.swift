import Foundation
import Testing
@testable import Bubo

/// Apri nel terminale: the command is typed and runs only on Return, in Bubo's terminal and in the script the Mac's
/// terminal opens. Terminal itself never opens: the script runs on a pseudo-terminal of the tests (spec 16).
extension TerminalTests {
    @Test func bubosTerminalTypesTheCommandWithoutRunningIt() async throws {
        let store = TerminalStore()
        store.shell = (URL(filePath: "/bin/sh"), ["-i"])
        let session = Session(id: UUID(), title: "Prova", project: folder,
                              workspace: Workspace(folder: folder, branch: "bubo/prova"), ports: 40_000..<40_010)

        store.type("echo GH-$((2 + 3))", in: session)

        #expect(store.isShown)
        let tab = try #require(store.tabs(of: session.id).first)
        let screen = Screen()
        tab.pty.onOutput = { screen.text += String(decoding: $0, as: UTF8.self) }
        tab.pty.write(ArraySlice(Array(" && echo PRONTO".utf8)))
        #expect(await screen.waitFor("PRONTO"))
        try await Task.sleep(for: .milliseconds(200))
        #expect(!screen.text.contains("GH-5"))

        tab.pty.write(ArraySlice(Array("\r".utf8)))
        #expect(await screen.waitFor("GH-5"))
        await store.closeAll(of: session.id)
    }

    @Test func theSystemTerminalScriptTypesTheCommandAndDeletesItself() async throws {
        var opened: [URL] = []
        let terminal = SystemTerminal(folder: folder) { opened.append($0); return true }

        try terminal.open(typing: "echo GH-$((2 + 3)) 'citato'")

        let script = try #require(opened.first)
        #expect(script.pathExtension == "command")
        #expect(FileManager.default.isExecutableFile(atPath: script.path))
        let environment = ["PATH": "/usr/bin:/bin", "TERM": "xterm-256color", "SHELL": "/bin/sh"]
        let pty = try PTYSession(folder: folder, environment: environment, shell: script, arguments: [])
        defer { Task { await pty.close() } }
        let screen = Screen()
        pty.onOutput = { screen.text += String(decoding: $0, as: UTF8.self) }

        #expect(await screen.waitFor("'citato'"), "the command is not typed: \(screen.text)")
        try await Task.sleep(for: .milliseconds(200))
        #expect(!screen.text.contains("GH-5"))
        #expect(!FileManager.default.fileExists(atPath: script.path))

        pty.write(ArraySlice(Array("\r".utf8)))
        #expect(await screen.waitFor("GH-5 citato"), "Return does not run it: \(screen.text)")
    }

    @Test func aTerminalThatDoesNotOpenLeavesNoScriptAndSaysTheCommand() throws {
        let terminal = SystemTerminal(folder: folder) { _ in false }

        #expect(throws: SystemTerminalError.self) { try terminal.open(typing: "brew install gh") }

        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        #expect(SystemTerminalError.notOpened(command: "brew install gh").errorDescription?.contains("brew install gh") == true)
    }
}
