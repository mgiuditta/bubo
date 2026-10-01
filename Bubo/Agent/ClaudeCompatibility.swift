import Foundation
import os

/// Which `claude` Bubo runs (spec 27): a minimum version, from `bridge/compat.json`, and no maximum.
///
/// The bridge reads the same file, at every `init`: the two sides never disagree on the minimum.
nonisolated struct ClaudeCompatibility: Equatable, Sendable {
    /// The oldest `claude` Bubo runs: the first with every option the bridge passes it.
    let minimumVersion: ClaudeVersion

    /// The compatibility in Bubo's bundle, copied there from `bridge/compat.json`.
    static let bundled = ClaudeCompatibility(file: Bundle.main.url(forResource: "compat", withExtension: "json"))

    /// Creates the compatibility with `minimumVersion`.
    init(minimumVersion: ClaudeVersion) {
        self.minimumVersion = minimumVersion
    }

    /// Reads the compatibility from `file`, the format of `bridge/compat.json`.
    ///
    /// Without a readable file there is no minimum: a broken bundle must not block every Sessione.
    init(file: URL?) {
        struct Compat: Decodable { let minimumClaudeVersion: String }
        guard let file, let data = try? Data(contentsOf: file),
              let compat = try? JSONDecoder().decode(Compat.self, from: data),
              let minimum = ClaudeVersion(compat.minimumClaudeVersion)
        else {
            Logger.agent.fault("compat.json unreadable: no minimum version for claude")
            self.init(minimumVersion: ClaudeVersion(major: 0, minor: 0, patch: 0))
            return
        }
        self.init(minimumVersion: minimum)
    }

    /// Whether `version`, as `claude --version` or `init` report it, is older than the minimum.
    ///
    /// A version Bubo cannot read is not: with no maximum, a format Bubo does not know is a newer `claude`.
    func isOutdated(_ version: String) -> Bool {
        guard let version = ClaudeVersion(version) else { return false }
        return version < minimumVersion
    }
}

/// A version of `claude`, compared as semver: `2.1.275-beta.1` comes before `2.1.275`.
nonisolated struct ClaudeVersion: Comparable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int
    /// Whether it is a prerelease, such as `-beta.1`.
    var isPrerelease = false

    /// Reads the version at the start of `text`, such as `2.1.286 (Claude Code)` or `v2.1.286`; missing parts are 0.
    ///
    /// Returns `nil` when `text` does not start with a number.
    init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        let start = text.first == "v" ? text.dropFirst() : Substring(text)
        let core = start.prefix { $0.isASCII && ($0.isNumber || $0 == ".") }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).prefix(3).map { Int($0) }
        guard let major = numbers.first ?? nil else { return nil }
        self.init(major: major, minor: numbers.dropFirst().first.flatMap { $0 } ?? 0,
                  patch: numbers.dropFirst(2).first.flatMap { $0 } ?? 0,
                  isPrerelease: start.dropFirst(core.count).first == "-")
    }

    /// Creates the version `major.minor.patch`.
    init(major: Int, minor: Int, patch: Int, isPrerelease: Bool = false) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.isPrerelease = isPrerelease
    }

    static func < (lhs: ClaudeVersion, rhs: ClaudeVersion) -> Bool {
        let left = [lhs.major, lhs.minor, lhs.patch], right = [rhs.major, rhs.minor, rhs.patch]
        return left == right ? lhs.isPrerelease && !rhs.isPrerelease : left.lexicographicallyPrecedes(right)
    }
}

/// A protocol capability that `claude` declares in `init`, for features to check instead of its version.
///
/// The set is open: values Bubo does not know are left out, and an older `claude` declares none.
nonisolated enum ClaudeCapability: String, Sendable {
    /// The interrupt's answer lists the queued messages that survive it.
    case interruptReceipt = "interrupt_receipt_v1"
    /// The interrupt can cancel the queued messages too.
    case interruptCancelQueued = "interrupt_cancel_queued_v1"
    /// `claude` accepts queued notifications.
    case queuedNotifications = "queued_notifications"
    /// The tool lists of in-process MCP servers can wait until the first message.
    case sdkMCPManifests = "sdk_mcp_manifests"
    /// In-process MCP servers can change their tools during the conversation.
    case sdkMCPToolsListChanged = "sdk_mcp_tools_list_changed"

    /// The capabilities Bubo knows among `values`; none when `claude` sent none.
    static func known(in values: [String]?) -> Set<ClaudeCapability> {
        Set((values ?? []).compactMap(ClaudeCapability.init(rawValue:)))
    }
}
