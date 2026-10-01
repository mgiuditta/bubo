import CryptoKit
import Foundation

/// Why `.bubo/regole.json` cannot be read: then no team rule applies, and the Progetto shows it in red.
nonisolated enum TeamRulesError: Error, Equatable {
    /// The file is not a JSON object with `version` 1 and only `allow`, `deny` and `ask`, each a list of rules.
    case invalid
    /// `.bubo` or the file is a link or not a regular file, or the file is too large: Bubo does not follow it.
    case unsafeLocation
}

/// The Regole di permesso a repo shares in `.bubo/regole.json` (ADR 0009): `{"version": 1, "allow": […],
/// "deny": […], "ask": […]}`, with the syntax of Claude Code's rules.
///
/// The file comes from whoever can push to the repo, so it is untrusted: `deny` and `ask` apply at once because they
/// only restrict; each `allow` is a voce that applies only once the user accepted that exact text (`TrustLedger`).
nonisolated struct TeamRules: Equatable, Sendable {
    /// The rules that allow, each a voce to accept.
    var allow: [String] = []
    /// The rules that refuse, in force at once.
    var deny: [String] = []
    /// The rules that always ask, in force at once.
    var ask: [String] = []

    /// The file, relative to the main checkout.
    static let path = ".bubo/regole.json"
    /// The largest file Bubo reads: rules are lines, not megabytes.
    static let maximumSize = 256 * 1024

    init(allow: [String] = [], deny: [String] = [], ask: [String] = []) {
        self.allow = allow
        self.deny = deny
        self.ask = ask
    }

    /// Reads the rules in `data`, each normalized.
    ///
    /// - Throws: `TeamRulesError.invalid` unless every key and rule is what the format allows.
    init(data: Data) throws(TeamRulesError) {
        guard data.count <= Self.maximumSize,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(object.keys).isSubset(of: ["version", "allow", "deny", "ask"]),
              let version = object["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1
        else { throw .invalid }
        func rules(_ key: String) throws(TeamRulesError) -> [String] {
            guard let value = object[key] else { return [] }
            guard let texts = value as? [String] else { throw .invalid }
            let rules = texts.map(Self.normalized)
            guard rules.allSatisfy({ !$0.contains("\0") && ProjectRule.isWellFormed($0) }) else { throw .invalid }
            return rules
        }
        allow = try rules("allow")
        deny = try rules("deny")
        ask = try rules("ask")
    }

    /// Reads `.bubo/regole.json` in the main checkout `root`; `nil` when there is none.
    ///
    /// - Throws: `TeamRulesError`: `unsafeLocation` for a link or a file that is not regular or too large, `invalid`
    ///   for one that cannot be read or is not in the format.
    static func read(inProject root: URL) throws(TeamRulesError) -> TeamRules? {
        let folder = root.appending(path: ".bubo")
        let file = root.appending(path: path)
        var status = stat()
        guard lstat(folder.path, &status) == 0 else { return nil }
        guard status.st_mode & S_IFMT == S_IFDIR else { throw .unsafeLocation }
        // Never through a link, which could point at another repo's file, and never blocking on a pipe.
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw errno == ELOOP ? .unsafeLocation : .invalid
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_size <= maximumSize else {
            throw .unsafeLocation
        }
        guard let data = try? handle.readToEnd() ?? Data() else { throw .invalid }
        return try TeamRules(data: data)
    }

    /// `text` as its hash is taken and as it applies: line ends as `\n`, spaces and tabs at the end of each line and
    /// empty lines at the end removed.
    static func normalized(_ text: String) -> String {
        let lines = text.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in String(line.reversed().drop { $0 == " " || $0 == "\t" }.reversed()) }
        return lines.reversed().drop(while: \.isEmpty).reversed().joined(separator: "\n")
    }

    /// The SHA-256 of the normalized `rule` in UTF-8, as lowercase hex: what an acceptance is bound to.
    static func hash(of rule: String) -> String {
        SHA256.hash(data: Data(normalized(rule).utf8)).map { byte in
            let digits = String(byte, radix: 16)
            return digits.count == 1 ? "0" + digits : digits
        }.joined()
    }
}
