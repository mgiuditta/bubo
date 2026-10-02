import Foundation

/// What OpenSSH asks Bubo's askpass helper.
nonisolated enum AskpassQuestion: Equatable, Sendable {
    /// The first connection to a host: its key is not in `known_hosts`. The fingerprint is that of the key the host
    /// presented, ED25519 when it has one.
    case newHostKey(HostKey)
    /// A passphrase or a password, which Bubo asks in a sheet and never keeps.
    case secret(prompt: String)

    /// The question in the text OpenSSH passes the helper.
    init(_ text: String) {
        if text.contains("authenticity of host"), let key = HostKey(presentedIn: text) {
            self = .newHostKey(key)
        } else {
            self = .secret(prompt: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// A host key as OpenSSH shows it: its type and its SHA256 fingerprint.
nonisolated struct HostKey: Codable, Equatable, Sendable {
    /// `ED25519`, `ECDSA` or `RSA`.
    let type: String
    /// `SHA256:…`.
    let fingerprint: String

    /// The key in the first-connection question: "ED25519 key fingerprint is SHA256:….".
    init?(presentedIn text: String) {
        guard let match = text.firstMatch(of: /(\w+) key fingerprint is (SHA256:[A-Za-z0-9+\/=]+)/) else { return nil }
        self.init(type: String(match.1), fingerprint: String(match.2))
    }

    init(type: String, fingerprint: String) {
        self.type = type
        self.fingerprint = fingerprint
    }
}

/// A host whose key is not the one in `known_hosts`: maybe an attack. Nothing connects to it until the user
/// removes the old key from a Terminale.
nonisolated struct HostKeyChange: Codable, Equatable, Sendable {
    /// The key `known_hosts` expects, when `ssh-keygen -F` finds it.
    var expected: String?
    /// The key the host presented.
    let received: HostKey

    /// The change OpenSSH reports on standard error, `nil` for any other failure.
    init?(reportedIn standardError: String) {
        guard standardError.contains("REMOTE HOST IDENTIFICATION HAS CHANGED"),
              let match = standardError.firstMatch(
                of: /fingerprint for the (\w+) key sent by the remote host is\s+(SHA256:[A-Za-z0-9+\/=]+)/)
        else { return nil }
        received = HostKey(type: String(match.1), fingerprint: String(match.2))
    }

    /// The fingerprint of the key of the same type in the output of `ssh-keygen -l -F <host>`.
    static func expectedFingerprint(of type: String, in keygenOutput: String) -> String? {
        keygenOutput.split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("#") }
            .compactMap { line -> HostKey? in
                // "myhost.lan ED25519 SHA256:…"
                guard let match = line.firstMatch(of: /\s(\w+)\s+(SHA256:[A-Za-z0-9+\/=]+)/) else { return nil }
                return HostKey(type: String(match.1), fingerprint: String(match.2))
            }
            .first { $0.type.caseInsensitiveCompare(type) == .orderedSame }?.fingerprint
    }
}

/// Fiducia e revoca of the Macchine (spec 23): the first connection asks the user, a changed key blocks.
///
/// The trust itself is OpenSSH's `known_hosts`; the gate only reads what OpenSSH reports and keeps Bubo from
/// trying a blocked host again.
nonisolated enum HostKeyGate {
    /// How a connection ended.
    enum Outcome: Equatable, Sendable {
        /// Connected; the command's output.
        case connected(String)
        /// The host's key changed: blocked.
        case keyChanged(HostKeyChange)
        /// The user refused the key or the passphrase.
        case refused
        /// Anything else, as OpenSSH wrote it.
        case failed(String)
    }

    /// The outcome of an `ssh` run, given whether the user refused one of its questions.
    static func outcome(of output: ProcessOutput, refusedQuestion: Bool) -> Outcome {
        if output.exitCode == 0 { return .connected(output.standardOutput) }
        if let change = HostKeyChange(reportedIn: output.standardError) { return .keyChanged(change) }
        if refusedQuestion { return .refused }
        let reason = output.standardError.split(whereSeparator: \.isNewline).last.map(String.init)
        return .failed(reason ?? "")
    }

    /// The command that removes the old key of `machine` from `known_hosts`, for the user to run in a Terminale.
    static func removalCommand(for machine: Machine) -> String {
        "ssh-keygen -R \(machine.knownHostsName)"
    }

    /// The command that shows the host's own fingerprint, to compare on the host before trusting it.
    static func verificationCommand(for key: HostKey) -> String {
        "ssh-keygen -lf /etc/ssh/ssh_host_\(key.type.lowercased())_key.pub"
    }
}
