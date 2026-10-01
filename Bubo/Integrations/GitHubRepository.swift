import Foundation

/// The GitHub repo of a Progetto, read from its git remote: the host too, so GitHub Enterprise works (spec 16).
nonisolated struct GitHubRepository: Equatable, Sendable {
    /// The GitHub host, such as `github.com`.
    var host: String
    var owner: String
    var name: String

    /// The repo as `gh --repo` takes it: `HOST/OWNER/REPO`.
    var argument: String { "\(host)/\(owner)/\(name)" }

    /// The repo a remote URL points to: `https://host/owner/repo(.git)`, `ssh://git@host[:port]/owner/repo(.git)` or
    /// `git@host:owner/repo(.git)`; `nil` for anything else, like a local path.
    init?(remote: String) {
        let remote = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let host: String
        let path: Substring
        if let url = URL(string: remote), let scheme = url.scheme, ["https", "http", "ssh", "git"].contains(scheme),
           let urlHost = url.host(), !urlHost.isEmpty {
            host = urlHost
            path = Substring(url.path(percentEncoded: false))
        } else if !remote.contains("://"), let colon = remote.firstIndex(of: ":"),
                  let at = remote[..<colon].lastIndex(of: "@") {
            host = String(remote[remote.index(after: at)..<colon])
            path = remote[remote.index(after: colon)...]
        } else {
            return nil
        }
        let parts = path.split(separator: "/")
        guard parts.count == 2, !host.isEmpty else { return nil }
        let name = parts[1].hasSuffix(".git") ? parts[1].dropLast(4) : parts[1]
        guard !parts[0].isEmpty, !name.isEmpty else { return nil }
        self.host = host.lowercased()
        owner = String(parts[0])
        self.name = String(name)
    }
}
