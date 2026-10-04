import Foundation

/// A computer of the user reached through SSH, as `ssh -G` resolves one alias of `~/.ssh/config`.
nonisolated struct Machine: Codable, Hashable, Identifiable, Sendable {
    /// The `Host` name in `~/.ssh/config`: what Bubo passes to `ssh`.
    let alias: String
    /// The account on the host, from `ssh -G`.
    let user: String
    /// The host's real name, from `ssh -G`; what `known_hosts` and `ssh-keygen -R` use.
    let hostname: String
    /// The SSH port, 22 unless the configuration says otherwise.
    var port = 22

    var id: String { alias }

    /// `utente@hostname`, as the menu and Impostazioni › Macchine show the Macchina.
    var address: String { "\(user)@\(hostname)" }

    /// The name `known_hosts` keeps the host's key under: `[hostname]:port` off the default port.
    var knownHostsName: String { port == 22 ? hostname : "[\(hostname)]:\(port)" }
}
