import Foundation
import Synchronization
import Testing
@testable import Bubo

struct SSHConfigReaderTests {
    /// The `ssh -G` runs of a reader.
    final class Calls: Sendable {
        let list = Mutex<[[String]]>([])
    }

    /// A `~/.ssh` folder of text files, with `Include` globs matched by prefix.
    static func reader(_ files: [String: String], resolved: [String: String] = [:],
                      calls: Calls = Calls()) -> SSHConfigReader {
        SSHConfigReader(
            sshFolder: URL(filePath: "/Users/ada/.ssh", directoryHint: .isDirectory),
            fileSystem: .init(
                contents: { files[$0.path] },
                paths: { pattern in
                    let prefix = pattern.replacing("*", with: "")
                    return files.keys.filter { pattern.contains("*") ? $0.hasPrefix(prefix) : $0 == pattern }.sorted()
                }),
            runner: ProcessRunner { _, arguments in
                calls.list.withLock { $0.append(arguments) }
                guard let output = resolved[arguments.last ?? ""] else {
                    return ProcessOutput(exitCode: 255, standardOutput: "")
                }
                return ProcessOutput(exitCode: 0, standardOutput: output)
            })
    }

    @Test func readsConcreteAliasesAndLeavesOutPatterns() {
        let reader = Self.reader(["/Users/ada/.ssh/config": """
            # Macchine di casa
            Host nas "studio mac"
              HostName nas.lan
            Host *.lan !gateway build?
            host=pi
            Host nas
            Match host foo
            """])
        #expect(reader.aliases() == ["nas", "studio mac", "pi"])
    }

    @Test func followsIncludesInLexicalOrderRelativeToTheSSHFolder() {
        let reader = Self.reader([
            "/Users/ada/.ssh/config": "Include config.d/*\nInclude ~/.ssh/extra\nHost last",
            "/Users/ada/.ssh/config.d/b": "Host beta",
            "/Users/ada/.ssh/config.d/a": "Host alpha\nInclude /Users/ada/.ssh/config",
            "/Users/ada/.ssh/extra": "Host extra",
        ])
        #expect(reader.aliases() == ["alpha", "beta", "extra", "last"])
    }

    @Test func resolvesEachAliasWithSSHG() async {
        let calls = Calls()
        let reader = Self.reader(["/Users/ada/.ssh/config": "Host nas gone"],
                                 resolved: ["nas": "user ada\nhostname nas.lan\nport 2222\nuser other\n"], calls: calls)
        let machines = await reader.machines()
        #expect(machines == [Machine(alias: "nas", user: "ada", hostname: "nas.lan", port: 2222)])
        #expect(calls.list.withLock { $0 } == [["-G", "--", "nas"], ["-G", "--", "gone"]])
    }

    @Test func emptyWithoutAConfiguration() {
        #expect(Self.reader([:]).aliases().isEmpty)
    }
}

struct SSHCommandTests {
    static let machine = Machine(alias: "nas", user: "ada", hostname: "nas.lan")
    static let folder = SSHCommand.controlFolder(home: URL(filePath: "/Users/ada", directoryHint: .isDirectory))

    @Test func neverTurnsOffHostKeyChecking() {
        let lists = [
            SSHCommand.arguments(running: "uname -sr", on: Self.machine, trust: .firstConnection, controlFolder: Self.folder),
            SSHCommand.arguments(running: "uname -sr", on: Self.machine, trust: .known, controlFolder: Self.folder),
            SSHCommand.checkArguments(for: Self.machine, controlFolder: Self.folder),
            SSHCommand.exitArguments(for: Self.machine, controlFolder: Self.folder),
        ]
        for arguments in lists {
            #expect(!arguments.contains { $0.lowercased().replacing(" ", with: "").contains("stricthostkeychecking=no") })
            #expect(!arguments.contains { $0.lowercased().contains("stricthostkeychecking=off") })
        }
    }

    @Test(arguments: [(SSHCommand.Trust.firstConnection, "ask"), (.known, "yes")])
    func alwaysSetsHostKeyCheckingOverTheUserConfiguration(trust: SSHCommand.Trust, value: String) {
        let arguments = SSHCommand.arguments(running: "true", on: Self.machine, trust: trust, controlFolder: Self.folder)
        #expect(arguments.starts(with: ["-o", "StrictHostKeyChecking=\(value)"]))
        #expect(arguments.suffix(3) == ["--", "nas", "true"])
    }

    @Test func controlSocketFitsMacOSLimitWithALongUserName() {
        let home = URL(filePath: "/Users/" + String(repeating: "u", count: 32), directoryHint: .isDirectory)
        let path = SSHCommand.controlPath(in: SSHCommand.controlFolder(home: home))
        // %C becomes a 40-character hash.
        let expanded = path.replacing("%C", with: String(repeating: "f", count: 40))
        #expect(expanded.utf8.count < SSHCommand.maximumSocketPathLength)
    }

    @Test func keepsBubosEnvironmentFromTheHost() {
        let askpass = Askpass(folder: URL(filePath: "/tmp/bubo-askpass-x"))
        let environment = SSHCommand.environment(askpass: askpass, from: [
            "HOME": "/Users/ada", "SSH_AUTH_SOCK": "/tmp/agent", "ANTHROPIC_API_KEY": "sk-ant-secret",
        ])
        #expect(environment["ANTHROPIC_API_KEY"] == nil)
        #expect(environment["SSH_AUTH_SOCK"] == "/tmp/agent")
        #expect(environment["SSH_ASKPASS"] == "/tmp/bubo-askpass-x/askpass")
        #expect(environment["SSH_ASKPASS_REQUIRE"] == "force")
    }
}

struct HostKeyGateTests {
    static let newHost = """
        The authenticity of host 'nas.lan (192.168.1.20)' can't be established.
        ED25519 key fingerprint is SHA256:YN7R0X2SEUWLztTqXjJvEP8PClPWEsV7aTIP9uaQ8yc.
        This key is not known by any other names.
        Are you sure you want to continue connecting (yes/no/[fingerprint])?
        """

    static let changed = """
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
        The fingerprint for the ECDSA key sent by the remote host is
        SHA256:Zm9vYmFyYmF6cXV4.
        Please contact your system administrator.
        Host key verification failed.
        """

    @Test func readsTheKeyTheHostPresented() {
        #expect(AskpassQuestion(Self.newHost) == .newHostKey(
            HostKey(type: "ED25519", fingerprint: "SHA256:YN7R0X2SEUWLztTqXjJvEP8PClPWEsV7aTIP9uaQ8yc")))
    }

    @Test func anyOtherQuestionIsASecret() {
        #expect(AskpassQuestion("Enter passphrase for key '/Users/ada/.ssh/id_ed25519': ")
                == .secret(prompt: "Enter passphrase for key '/Users/ada/.ssh/id_ed25519':"))
    }

    @Test func aChangedKeyBlocks() {
        let outcome = HostKeyGate.outcome(of: ProcessOutput(exitCode: 255, standardOutput: "", standardError: Self.changed),
                                          refusedQuestion: false)
        #expect(outcome == .keyChanged(HostKeyChange(reportedIn: Self.changed)!))
        #expect(HostKeyChange(reportedIn: Self.changed)?.received == HostKey(type: "ECDSA", fingerprint: "SHA256:Zm9vYmFyYmF6cXV4"))
    }

    @Test func readsTheExpectedKeyOfTheSameType() {
        let output = """
            # Host nas.lan found: line 4
            nas.lan RSA SHA256:cnNhcnNh
            nas.lan ECDSA SHA256:ZWNkc2E
            """
        #expect(HostKeyChange.expectedFingerprint(of: "ECDSA", in: output) == "SHA256:ZWNkc2E")
        #expect(HostKeyChange.expectedFingerprint(of: "ED25519", in: output) == nil)
    }

    @Test func removalCommandNamesTheHostAsKnownHostsDoes() {
        #expect(HostKeyGate.removalCommand(for: SSHCommandTests.machine) == "ssh-keygen -R nas.lan")
        let other = Machine(alias: "box", user: "ada", hostname: "box.lan", port: 2222)
        #expect(HostKeyGate.removalCommand(for: other) == "ssh-keygen -R [box.lan]:2222")
    }
}

struct AskpassTests {
    @Test func theHelperPrintsTheAnswerGivenThroughItsFIFO() async throws {
        let askpass = try Askpass.make()
        defer { askpass.remove() }
        let runner = ProcessRunner.live(environment: [Askpass.folderVariable: askpass.folder.path, "PATH": "/usr/bin:/bin"])
        async let output = runner.run(askpass.script, ["Enter passphrase for key 'id':"])
        var questions: [(id: String, text: String)] = []
        for _ in 0..<100 where questions.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
            questions = askpass.takeQuestions()
        }
        let question = try #require(questions.first)
        #expect(question.text == "Enter passphrase for key 'id':")
        await askpass.answer(question.id, with: "a b $c")
        let result = try await output
        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "a b $c\n")
        // Nothing of the answer stays on disk.
        #expect(try FileManager.default.contentsOfDirectory(atPath: askpass.folder.path) == ["askpass"])
    }

    @Test func aRefusalMakesTheHelperFail() async throws {
        let askpass = try Askpass.make()
        defer { askpass.remove() }
        let runner = ProcessRunner.live(environment: [Askpass.folderVariable: askpass.folder.path, "PATH": "/usr/bin:/bin"])
        async let output = runner.run(askpass.script, ["Are you sure?"])
        var questions: [(id: String, text: String)] = []
        for _ in 0..<100 where questions.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
            questions = askpass.takeQuestions()
        }
        await askpass.answer(try #require(questions.first).id, with: nil)
        #expect(try await output.exitCode != 0)
    }
}

@MainActor
struct MachineStoreTests {
    /// An OpenSSH that never connects: it records each run and asks the questions it is given.
    final class FakeSSH: Sendable {
        let runs = Mutex<[[String]]>([])
        let questions: [AskpassQuestion]
        let output: ProcessOutput

        init(questions: [AskpassQuestion] = [], output: ProcessOutput) {
            self.questions = questions
            self.output = output
        }

        var client: SSHClient {
            SSHClient { [self] arguments, ask in
                runs.withLock { $0.append(arguments) }
                if arguments.contains("-O") { return .init(output: ProcessOutput(exitCode: 255, standardOutput: "")) }
                var refused = false
                for question in questions {
                    if await ask(question) == nil { refused = true }
                }
                return .init(output: refused ? ProcessOutput(exitCode: 255, standardOutput: "") : output,
                             refusedQuestion: refused)
            }
        }

        /// The runs that reach the host, leaving out `-O` requests to the local ControlMaster.
        var connections: Int { runs.withLock { $0.filter { !$0.contains("-O") }.count } }
    }

    let file = URL.temporaryDirectory.appending(path: "Macchine-\(UUID().uuidString).json")
    let machine = SSHCommandTests.machine

    func store(_ ssh: FakeSSH) -> MachineStore {
        MachineStore(
            reader: SSHConfigReaderTests.reader([:]), client: ssh.client,
            keygen: ProcessRunner { _, _ in ProcessOutput(exitCode: 0, standardOutput: "nas.lan ECDSA SHA256:b2xk\n") },
            controlFolder: URL.temporaryDirectory.appending(path: "cm-\(UUID().uuidString)"), file: file)
    }

    /// Connects, answering each question with the next of `answers` as soon as it is shown.
    func connect(_ store: MachineStore, answers: [String?]) async {
        let connection = Task { await store.connect(machine) }
        for answer in answers {
            while store.question == nil { await Task.yield() }
            store.answer(answer)
        }
        await connection.value
    }

    @Test func firstConnectionAsksTheKeyAndRemembersIt() async throws {
        let key = HostKey(type: "ED25519", fingerprint: "SHA256:bmV3")
        let ssh = FakeSSH(questions: [.newHostKey(key)], output: ProcessOutput(exitCode: 0, standardOutput: "Linux 6.8\n"))
        let store = self.store(ssh)
        await connect(store, answers: ["yes"])
        #expect(store.status(of: machine) == .connected)
        #expect(store.records["nas"]?.confirmedKey == "SHA256:bmV3")
        #expect(store.records["nas"]?.system == "Linux 6.8")
        let arguments = try #require(ssh.runs.withLock { $0.first })
        #expect(arguments.contains("StrictHostKeyChecking=ask"))
    }

    @Test func refusingTheKeyLeavesNoMachine() async {
        let ssh = FakeSSH(questions: [.newHostKey(HostKey(type: "ED25519", fingerprint: "SHA256:bmV3"))],
                          output: ProcessOutput(exitCode: 0, standardOutput: "Linux\n"))
        let store = self.store(ssh)
        await connect(store, answers: [nil])
        #expect(store.records.isEmpty)
        #expect(store.status(of: machine) == nil)
    }

    @Test func aChangedKeyBlocksEveryLaterConnection() async {
        let ssh = FakeSSH(output: ProcessOutput(exitCode: 255, standardOutput: "", standardError: HostKeyGateTests.changed))
        let store = self.store(ssh)
        await store.connect(machine)
        #expect(store.status(of: machine) == .blocked)
        #expect(store.records["nas"]?.keyChange?.expected == "SHA256:b2xk")
        #expect(ssh.connections == 1)

        await store.connect(machine)
        await store.refresh()
        // A new launch reads the block back and still refuses.
        let relaunched = self.store(ssh)
        await relaunched.connect(machine)
        #expect(relaunched.status(of: machine) == .blocked)
        #expect(ssh.connections == 1)
    }

    @Test func keepsNoPassphrase() async throws {
        let ssh = FakeSSH(questions: [.secret(prompt: "Enter passphrase for key 'id':")],
                          output: ProcessOutput(exitCode: 0, standardOutput: "Darwin 25.0\n"))
        let store = self.store(ssh)
        await connect(store, answers: ["correct horse battery staple"])
        #expect(store.status(of: machine) == .connected)
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(!saved.contains("correct horse"))
        #expect(!saved.contains("PRIVATE KEY"))
    }

    @Test func removeClosesTheControlMasterAndForgets() async throws {
        let ssh = FakeSSH(output: ProcessOutput(exitCode: 0, standardOutput: "Linux\n"))
        let store = self.store(ssh)
        await store.connect(machine)
        await store.remove(machine)
        #expect(store.records.isEmpty)
        let exit = try #require(ssh.runs.withLock { $0.last })
        #expect(exit.contains("-O") && exit.contains("exit") && exit.last == "nas")
    }
}
