import Darwin
import Foundation
import Testing
@testable import Bubo

/// The terminal of a Sessione: a real shell through the bundle's launcher, with the disclaim, a controlling
/// terminal, the Sessione's folder and ports, and nothing left alive once it closes (spec 15).
@MainActor
@Suite(.serialized)
struct TerminalTests {
    /// What a shell wrote so far.
    final class Screen {
        var text = ""

        /// Waits up to `timeout` for `marker` to appear.
        func waitFor(_ marker: String, timeout: Duration = .seconds(5)) async -> Bool {
            let deadline = ContinuousClock.now + timeout
            while !text.contains(marker) {
                guard ContinuousClock.now < deadline else { return false }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return true
        }
    }

    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "TerminalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// The Sessione the shells start for, in `folder` with ten ports.
    private var session: Session {
        Session(id: UUID(), title: "Prova", project: folder, workspace: Workspace(folder: folder, branch: "bubo/prova"),
                ports: 40_000..<40_010)
    }

    /// An interactive `sh` without profile, so only the terminal is measured.
    private func start() throws -> (PTYSession, Screen) {
        var environment = ChildEnvironment.makeForTerminal(of: session)
        environment["PS1"] = "$ "
        environment["BASH_SILENCE_DEPRECATION_WARNING"] = "1"
        let pty = try PTYSession(folder: folder, environment: environment, shell: URL(filePath: "/bin/sh"),
                                 arguments: ["-i"])
        let screen = Screen()
        pty.onOutput = { screen.text += String(decoding: $0, as: UTF8.self) }
        return (pty, screen)
    }

    private func type(_ text: String, in pty: PTYSession) {
        pty.write(ArraySlice(Array(text.utf8)))
    }

    @Test func theShellHasAControllingTerminal() async throws {
        let (pty, screen) = try start()
        defer { Task { await pty.close() } }
        type("ps -o tty= -p $$; exec 3</dev/tty && echo TTY-$((1 + 1))\n", in: pty)
        #expect(await screen.waitFor("TTY-2"), "/dev/tty does not open: \(screen.text)")
        #expect(screen.text.contains("ttys"), "ps shows no tty: \(screen.text)")
    }

    @Test func controlCInterruptsTheCommandInFront() async throws {
        let (pty, screen) = try start()
        defer { Task { await pty.close() } }
        #expect(await screen.waitFor("$ "))
        type("sleep 30\n", in: pty)
        try await Task.sleep(for: .milliseconds(300))
        type("\u{03}", in: pty)
        type("echo AFTER-$((2 + 3))\n", in: pty)
        #expect(await screen.waitFor("AFTER-5", timeout: .seconds(3)), "⌃C did not stop sleep: \(screen.text)")
    }

    @Test func theShellStartsInTheFolderWithTheSessionePorts() async throws {
        let (pty, screen) = try start()
        defer { Task { await pty.close() } }
        type("echo \"D-$(pwd -P)\" \"P-$PORT-$BUBO_PORT-$BUBO_PORTS\"\n", in: pty)
        // The temporary folder is behind a symbolic link: the end of its path is enough.
        #expect(await screen.waitFor("/\(folder.lastPathComponent) P-40000-40000-40000-40009"), "\(screen.text)")
    }

    @Test func nothingInTheTerminalHasBuboAsResponsible() async throws {
        let responsible = try #require(Self.responsiblePID)
        let (pty, screen) = try start()
        defer { Task { await pty.close() } }
        type("sleep 30 & echo JOB-$((0 + 1))\n", in: pty)
        #expect(await screen.waitFor("JOB-1"), "\(screen.text)")
        try await Task.sleep(for: .milliseconds(100))
        let processes = pty.processes
        #expect(processes.count >= 2)
        for process in processes {
            #expect(responsible(process) != getpid(), "\(process) has Bubo as responsible")
        }
        #expect(responsible(pty.pid) == pty.pid)
    }

    @Test func closingLeavesNoProcessAlive() async throws {
        let (pty, screen) = try start()
        // A job that ignores the hang-up, and one stopped in the background.
        type("sh -c 'trap \"\" HUP; sleep 100' & sleep 100 & echo JOBS-$((3 + 4))\n", in: pty)
        #expect(await screen.waitFor("JOBS-7"))
        try await Task.sleep(for: .milliseconds(200))
        let processes = pty.processes
        #expect(processes.count >= 4, "\(processes)")
        await pty.close()
        let deadline = ContinuousClock.now + .seconds(2)
        while processes.contains(where: PTYSession.isAlive) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(processes.filter(PTYSession.isAlive).isEmpty)
    }

    @Test func theFirstPromptComesInUnder100Milliseconds() async throws {
        var durations: [Duration] = []
        for _ in 0..<20 {
            let opening = ContinuousClock.now
            let (pty, screen) = try start()
            #expect(await screen.waitFor("$ "))
            durations.append(ContinuousClock.now - opening)
            await pty.close()
        }
        let sorted = durations.sorted()
        let median = sorted[sorted.count / 2]
        print("Terminal first prompt over 20 openings: median \(median), max \(sorted.last ?? .zero)")
        #expect(median < .milliseconds(100))
    }

    @Test func theStoreOpensTerminalsOnlyWhereASessioneHasItsOwnFolder() async throws {
        let store = TerminalStore()
        store.shell = (URL(filePath: "/bin/sh"), ["-i"])
        var onCheckout = session
        onCheckout.isOnCheckout = true
        store.show(onCheckout)
        #expect(!store.isShown)
        #expect(store.tabs.isEmpty)

        let session = session
        store.show(session)
        #expect(store.isShown)
        #expect(store.tabs(of: session.id).count == 1)
        store.openTab()
        #expect(store.tabs(of: session.id).count == 2)
        let processes = store.tabs(of: session.id).flatMap(\.pty.processes)

        await store.closeAll(of: session.id)
        #expect(store.tabs.isEmpty)
        #expect(!store.isShown)
        try await Task.sleep(for: .milliseconds(100))
        #expect(processes.filter(PTYSession.isAlive).isEmpty)
    }

    @Test func quittingLeavesNoProcessAlive() async throws {
        let store = TerminalStore()
        store.shell = (URL(filePath: "/bin/sh"), ["-i"])
        store.show(session)
        let tab = try #require(store.tabs.values.first?.first)
        let screen = Screen()
        tab.pty.onOutput = { screen.text += String(decoding: $0, as: UTF8.self) }
        tab.pty.write(ArraySlice(Array("sleep 100 & echo Q-$((4 + 5))\n".utf8)))
        #expect(await screen.waitFor("Q-9"))
        let processes = tab.pty.processes
        #expect(processes.count >= 2)

        store.closeAllBeforeQuitting()
        #expect(processes.filter(PTYSession.isAlive).isEmpty)
    }

    @Test func aSessioneHasATerminalFolderOnlyWhileAperta() {
        var session = session
        #expect(session.terminalFolder == folder)
        session.phase = .archiviata
        #expect(session.terminalFolder == nil)
        session.phase = .aperta
        session.workspace = nil
        #expect(session.terminalFolder == nil)
    }

    private typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t

    /// `responsibility_get_pid_responsible_for_pid`, the SPI that tells who answers for a process in TCC.
    private static let responsiblePID: ResponsiblePID? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: ResponsiblePID.self)
    }()
}
