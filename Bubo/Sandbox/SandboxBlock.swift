import Foundation

/// Something the Sandbox stopped a command from doing, with its path or host (spec 22), as the bridge read it from
/// the command's `sandbox_violations`. The text comes from the command and the system: shown verbatim, never trusted.
nonisolated struct SandboxBlock: Hashable, Sendable, Decodable {
    /// What was stopped.
    enum Kind: String, Sendable {
        case write, read, network, other
    }

    let kind: Kind
    /// The path, the host for the network, or the whole line when it could not be read.
    let target: String
    /// The operation as Seatbelt names it, such as `mach-lookup`; only for `other`.
    var operation: String?

    private enum CodingKeys: String, CodingKey {
        case kind, target, operation
    }

    init(kind: Kind, target: String, operation: String? = nil) {
        self.kind = kind
        self.target = target
        self.operation = operation
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A kind from a newer bridge is still a block, shown with its target.
        kind = Kind(rawValue: try container.decode(String.self, forKey: .kind)) ?? .other
        target = try container.decode(String.self, forKey: .target)
        operation = try container.decodeIfPresent(String.self, forKey: .operation)
    }

    /// The line in the Sessione, the same the agent reads.
    var line: String {
        switch kind {
        case .write: String(localized: "Bloccato dalla sandbox: scrittura in \(target)")
        case .read: String(localized: "Bloccato dalla sandbox: lettura di \(target)")
        case .network: String(localized: "Bloccato dalla sandbox: rete verso \(target)")
        case .other:
            if let operation {
                String(localized: "Bloccato dalla sandbox: \(operation) su \(target)")
            } else {
                String(localized: "Bloccato dalla sandbox: \(target)")
            }
        }
    }

    /// What Consenti in questo Progetto would add: the host, or the folder of the write; `nil` for reads, which
    /// the Sandbox denies on purpose (credentials), for anything else, and for what is too wide to open.
    var allowance: SandboxAllowance? {
        switch kind {
        case .write: .folder(ofBlocked: target)
        case .network: .domain(from: target)
        case .read, .other: nil
        }
    }
}
