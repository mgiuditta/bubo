import Foundation

/// A host or a folder the user let the Sandbox reach in a Progetto (spec 22), beyond the fixed preset.
nonisolated enum SandboxAllowance: Hashable, Sendable {
    /// Sandboxed commands reach this host without asking.
    case domain(String)
    /// Sandboxed commands, Edit and Write also write in this folder.
    case folder(String)

    /// The host as the Sandbox lists it, lowercased; `nil` for anything but a plain domain name or address: no
    /// wildcard, port, path or IPv6 address.
    static func domain(from host: String) -> Self? {
        let host = host.lowercased()
        guard host.wholeMatch(of: /[a-z0-9]([a-z0-9.-]*[a-z0-9])?/) != nil else { return nil }
        return .domain(host)
    }

    /// The folder a blocked write happened in: the exact folder of `path`, never one above it.
    ///
    /// `nil` when that folder is too wide to open: the root, a top-level folder such as `/Users` or `/tmp`, the home
    /// folder or a folder above it, or a path that is not absolute or goes up with `..`.
    static func folder(ofBlocked path: String, home: String = NSHomeDirectory()) -> Self? {
        guard path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return nil }
        let folder = URL(filePath: path).deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
        let trimmed = folder.count > 1 && folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard trimmed.split(separator: "/").count >= 2, trimmed != home, !home.hasPrefix(trimmed + "/") else { return nil }
        return .folder(trimmed)
    }
}

/// The hosts and the folders the user let the Sandbox reach in a Progetto, in the order they were added.
nonisolated struct SandboxAllowances: Equatable, Sendable {
    var domains: [String] = []
    var folders: [String] = []

    /// Whether `allowance` is among them.
    func contains(_ allowance: SandboxAllowance) -> Bool {
        switch allowance {
        case let .domain(host): domains.contains(host)
        case let .folder(path): folders.contains(path)
        }
    }
}
