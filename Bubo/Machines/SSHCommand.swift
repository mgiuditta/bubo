import Foundation

/// The arguments of every `ssh` Bubo runs: the only place that writes them.
///
/// Each one fixes `StrictHostKeyChecking`, so that a `no` in the user's `~/.ssh/config` never lets a changed host
/// key through: `ask` until the user trusted the host in Bubo, `yes` after. Both refuse a changed key; neither is
/// ever `no` (spec 23, Fiducia e revoca).
nonisolated enum SSHCommand {
    /// The system's OpenSSH.
    static let executable = URL(filePath: "/usr/bin/ssh")
    /// The longest path of a Unix socket on macOS, terminator included.
    static let maximumSocketPathLength = 104

    /// How far Bubo trusts a Macchina's host key.
    enum Trust: Equatable, Sendable {
        /// Never confirmed in Bubo: OpenSSH asks for an unknown key, through Bubo's askpass sheet.
        case firstConnection
        /// Confirmed once: any key not in `known_hosts` is refused.
        case known

        /// The value of `StrictHostKeyChecking`.
        var strictHostKeyChecking: String {
            switch self {
            case .firstConnection: "ask"
            case .known: "yes"
            }
        }
    }

    /// The folder of the ControlMaster sockets: short, under `~/.ssh`, because a socket's path cannot pass 104 bytes.
    static func controlFolder(home: URL = .homeDirectory) -> URL {
        home.appending(path: ".ssh/bubo", directoryHint: .isDirectory)
    }

    /// The `ControlPath` of every connection: one ControlMaster per Macchina, named by OpenSSH's 40-character hash.
    static func controlPath(in folder: URL) -> String {
        folder.appending(path: "%C").path
    }

    /// The options every connection shares: trust, one ControlMaster per Macchina, keepalive.
    static func options(trust: Trust, controlFolder: URL) -> [String] {
        [
            "-o", "StrictHostKeyChecking=\(trust.strictHostKeyChecking)",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath(in: controlFolder))",
            "-o", "ControlPersist=600",
            "-o", "ServerAliveInterval=10",
            "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=10",
        ]
    }

    /// Runs `command` on `machine`, without a terminal.
    static func arguments(running command: String, on machine: Machine, trust: Trust, controlFolder: URL) -> [String] {
        options(trust: trust, controlFolder: controlFolder) + ["-T", "--", machine.alias, command]
    }

    /// Asks the ControlMaster of `machine` whether it is up; it never opens a connection.
    static func checkArguments(for machine: Machine, controlFolder: URL) -> [String] {
        ["-o", "ControlPath=\(controlPath(in: controlFolder))", "-O", "check", "--", machine.alias]
    }

    /// Closes the ControlMaster of `machine`, and with it every connection Bubo has to the host.
    static func exitArguments(for machine: Machine, controlFolder: URL) -> [String] {
        ["-o", "ControlPath=\(controlPath(in: controlFolder))", "-O", "exit", "--", machine.alias]
    }

    /// The environment of `ssh`: only what OpenSSH needs, so that a `SendEnv` of the user's configuration cannot
    /// send the host anything of Bubo's, plus the askpass helper, which shows the questions in Bubo's sheets.
    static func environment(askpass: Askpass, from inherited: [String: String]) -> [String: String] {
        let kept = ["HOME", "USER", "LOGNAME", "PATH", "SHELL", "TMPDIR", "LANG", "SSH_AUTH_SOCK"]
        var environment = inherited.filter { kept.contains($0.key) }
        environment["SSH_ASKPASS"] = askpass.script.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment[Askpass.folderVariable] = askpass.folder.path
        return environment
    }
}
