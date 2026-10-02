import Foundation

/// `manifest.json`, the first file of a Consegna's content (spec 24, Formato `.bubo`): what the receiver needs to
/// make the Bozza, fetch the branch and resume the conversation.
nonisolated struct DeliveryManifest: Codable, Equatable, Sendable {
    /// What the Consegna carries, as counted by the cleaning.
    struct Counts: Codable, Equatable, Sendable {
        var messages: Int
        var subagents: Int
        var reasoningBlocksRemoved: Int
        var secretsRemoved: Int
    }

    /// The version of this manifest's shape.
    var version = 1
    /// The Consegna, the same if it is opened twice.
    var id: UUID
    var title: String
    var person: String
    var machine: String
    /// The `origin` URL of the Progetto; `nil` without a remote.
    var remote: String?
    /// The commit the branch starts after; `nil` when the bundle has the whole history or there is no branch.
    var baseCommit: String?
    /// The Sessione's branch on the sender's Mac.
    var branch: String?
    /// The ref inside `ramo.bundle` to fetch; `nil` without a bundle.
    var bundleRef: String?
    /// The new `sessionId` of the cleaned transcript.
    var sessionID: String
    /// The `claude` version that wrote the transcript, from its lines.
    var claudeVersion: String?
    var counts: Counts

    /// The file names inside the archive.
    static let fileName = "manifest.json"
    static let transcriptName = "transcript.jsonl"
    static let bundleName = "ramo.bundle"
    static let subagentsFolder = "subagents"
    static let toolResultsFolder = "tool-results"
}
