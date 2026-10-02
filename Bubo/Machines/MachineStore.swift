import Foundation
import Observation
import os

/// How a Macchina is now, as its status dot shows it.
nonisolated enum MachineStatus: Equatable, Sendable {
    /// Its ControlMaster is up.
    case connected
    /// The last connection failed.
    case unreachable
    /// Its host key changed: nothing connects until the user removes the old key.
    case blocked
}

/// What Bubo keeps of a Macchina it connected to: never a key, a passphrase or a password.
nonisolated struct MachineRecord: Codable, Equatable, Sendable {
    var machine: Machine
    /// The fingerprint the user confirmed at the first connection, as a reminder: the trust is in `known_hosts`.
    var confirmedKey: String?
    /// `uname -sr` of the host.
    var system: String?
    /// The change that blocks the Macchina; `nil` while it is not blocked.
    var keyChange: HostKeyChange?
}

/// An OpenSSH question waiting for the user, in a sheet.
struct MachineQuestion: Identifiable, Equatable {
    let id = UUID()
    let machine: Machine
    let question: AskpassQuestion
}

/// The Macchine: the hosts of `~/.ssh/config`, the ones Bubo connected to, and their state.
///
/// Every `ssh` that reaches a host starts in ``connect(_:)``, which refuses a blocked Macchina without running
/// anything: Riprendi and Porta in Bubo will go through it too.
@Observable
final class MachineStore {
    /// The hosts of `~/.ssh/config`, in its order.
    private(set) var hosts: [Machine] = []
    /// The Macchine Bubo connected to, by alias.
    private(set) var records: [String: MachineRecord] = [:]
    /// The question OpenSSH is asking now; answered with ``answer(_:)``.
    private(set) var question: MachineQuestion?
    /// The alias being connected, one at a time.
    private(set) var connecting: String?
    /// Why the last connection failed, by alias.
    private(set) var failures: [String: String] = [:]
    private var statuses: [String: MachineStatus] = [:]
    @ObservationIgnored private var pendingAnswer: CheckedContinuation<String?, Never>?
    /// The fingerprint the user trusted during the connection in progress, by alias.
    @ObservationIgnored private var confirmedKeys: [String: String] = [:]

    @ObservationIgnored private let reader: SSHConfigReader
    @ObservationIgnored private let client: SSHClient
    /// Runs `ssh-keygen`, to read the key `known_hosts` expects.
    @ObservationIgnored private let keygen: ProcessRunner
    @ObservationIgnored private let controlFolder: URL
    @ObservationIgnored private let file: URL?

    init(reader: SSHConfigReader = SSHConfigReader(), client: SSHClient = .live, keygen: ProcessRunner = .live,
         controlFolder: URL = SSHCommand.controlFolder(), file: URL? = MachineStore.defaultFile) {
        self.reader = reader
        self.client = client
        self.keygen = keygen
        self.controlFolder = controlFolder
        self.file = file
        load()
    }

    /// `Macchine.json` in Bubo's Application Support folder.
    static var defaultFile: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                                     create: true)
            .appending(path: "Bubo/Macchine.json")
    }

    /// The hosts of the configuration plus the Macchine Bubo knows that left it, which can still be removed.
    var machines: [Machine] {
        hosts + records.values.map(\.machine).filter { machine in !hosts.contains { $0.alias == machine.alias } }
            .sorted { $0.alias < $1.alias }
    }

    /// The status of a Macchina; `nil` before its first connection or while it is idle.
    func status(of machine: Machine) -> MachineStatus? {
        records[machine.alias]?.keyChange == nil ? statuses[machine.alias] : .blocked
    }

    /// Whether Bubo never connected to the Macchina: "nuova" in the menu.
    func isNew(_ machine: Machine) -> Bool {
        records[machine.alias] == nil
    }

    /// Reads `~/.ssh/config` again and asks each known ControlMaster whether it is up, without connecting.
    func refresh() async {
        hosts = await reader.machines()
        for record in records.values where record.keyChange == nil {
            let alias = record.machine.alias
            let arguments = SSHCommand.checkArguments(for: record.machine, controlFolder: controlFolder)
            let run = try? await client.run(arguments) { _ in nil }
            if run?.output.exitCode == 0 {
                statuses[alias] = .connected
            } else if statuses[alias] == .connected {
                statuses[alias] = nil
            }
        }
    }

    /// Connects to `machine` and reads its system; OpenSSH's questions come to ``question``.
    ///
    /// A blocked Macchina is refused before `ssh` runs: 0 connections. A new key is asked to the user, a changed
    /// one blocks the Macchina.
    func connect(_ machine: Machine) async {
        guard records[machine.alias]?.keyChange == nil else {
            Logger.machines.notice("Macchina \(machine.alias, privacy: .private(mask: .hash)) blocked: not connecting")
            return
        }
        guard connecting == nil else { return }
        connecting = machine.alias
        defer { connecting = nil }
        failures[machine.alias] = nil
        try? FileManager.default.createDirectory(at: controlFolder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        confirmedKeys[machine.alias] = nil
        let arguments = SSHCommand.arguments(running: "uname -sr", on: machine, trust: .firstConnection,
                                             controlFolder: controlFolder)
        let outcome: HostKeyGate.Outcome
        do {
            let run = try await client.run(arguments) { [weak self] question in
                await self?.ask(question, for: machine)
            }
            outcome = HostKeyGate.outcome(of: run.output, refusedQuestion: run.refusedQuestion)
        } catch {
            outcome = .failed(error.localizedDescription)
        }
        await record(outcome, of: machine, confirmedKey: confirmedKeys.removeValue(forKey: machine.alias))
    }

    /// Lets a blocked Macchina be tried again, once the user removed the old key from `known_hosts`: the next
    /// connection asks for the new key like a first one, and blocks again if the key still differs.
    func unblock(_ machine: Machine) {
        records[machine.alias]?.keyChange = nil
        statuses[machine.alias] = nil
        save()
    }

    /// Rimuovi Macchina: closes every connection with `ssh -O exit` and forgets the Macchina; the key stays in
    /// `known_hosts`, which is the user's.
    func remove(_ machine: Machine) async {
        _ = try? await client.run(SSHCommand.exitArguments(for: machine, controlFolder: controlFolder)) { _ in nil }
        records[machine.alias] = nil
        statuses[machine.alias] = nil
        failures[machine.alias] = nil
        save()
        Logger.machines.notice("Macchina \(machine.alias, privacy: .private(mask: .hash)) removed")
    }

    /// Answers the question shown: `nil` refuses it.
    func answer(_ text: String?) {
        question = nil
        pendingAnswer?.resume(returning: text)
        pendingAnswer = nil
    }

    private func ask(_ asked: AskpassQuestion, for machine: Machine) async -> String? {
        let answer = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingAnswer?.resume(returning: nil)
                pendingAnswer = continuation
                question = MachineQuestion(machine: machine, question: asked)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.answer(nil) }
        }
        if case .newHostKey(let key) = asked, answer != nil { confirmedKeys[machine.alias] = key.fingerprint }
        return answer
    }

    private func record(_ outcome: HostKeyGate.Outcome, of machine: Machine, confirmedKey: String?) async {
        var record = records[machine.alias] ?? MachineRecord(machine: machine)
        record.machine = machine
        switch outcome {
        case .connected(let system):
            record.system = system.trimmingCharacters(in: .whitespacesAndNewlines)
            if let confirmedKey { record.confirmedKey = confirmedKey }
            records[machine.alias] = record
            statuses[machine.alias] = .connected
            Logger.machines.notice("Macchina \(machine.alias, privacy: .private(mask: .hash)) connected")
        case .keyChanged(var change):
            change.expected = await expectedKey(of: machine, type: change.received.type)
            record.keyChange = change
            records[machine.alias] = record
            Logger.machines.error("Macchina \(machine.alias, privacy: .private(mask: .hash)): host key changed, blocked")
        case .refused:
            break
        case .failed(let reason):
            failures[machine.alias] = reason
            if records[machine.alias] != nil { statuses[machine.alias] = .unreachable }
            Logger.machines.error("Macchina \(machine.alias, privacy: .private(mask: .hash)) unreachable: \(reason, privacy: .public)")
        }
        save()
    }

    /// The fingerprint `known_hosts` keeps for the host, of the type it presented.
    private func expectedKey(of machine: Machine, type: String) async -> String? {
        let executable = URL(filePath: "/usr/bin/ssh-keygen")
        guard let output = try? await keygen.run(executable, ["-l", "-F", machine.knownHostsName]) else { return nil }
        return HostKeyChange.expectedFingerprint(of: type, in: output.standardOutput)
    }

    private func load() {
        guard let file, let data = try? Data(contentsOf: file) else { return }
        do {
            records = try JSONDecoder().decode([String: MachineRecord].self, from: data)
        } catch {
            Logger.machines.error("Macchine unreadable: \(error)")
        }
    }

    private func save() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: file, options: .atomic)
        } catch {
            Logger.machines.error("Macchine not saved: \(error)")
        }
    }
}

extension Logger {
    nonisolated static let machines = Logger(subsystem: "com.mgiuditta.bubo", category: "machines")
}
