import Foundation

/// A Telecomando record as it sits in iCloud: clear, non-sensitive metadata and an encrypted payload.
///
/// Titles, Projects, commands and paths never go in the metadata (spec 21).
public struct RemoteRecord: Codable, Sendable, Equatable, Identifiable {
    /// The kinds of record.
    public enum Kind: String, Codable, Sendable {
        case heartbeat, sessionCard, request, verdict, command
    }

    /// The random record ID, also the associated data of the payload.
    public let id: String
    /// The kind of record.
    public let kind: Kind
    /// The random identifier of the Mac.
    public let macID: UUID
    /// The paired iPhone the payload is encrypted for.
    public let deviceID: UUID
    /// When the record may be deleted.
    public let expiresAt: Date
    /// The payload, sealed by ``RecordSealer`` with the pair's key.
    public let payload: Data

    /// Creates a record from its parts.
    public init(id: String = UUID().uuidString, kind: Kind, macID: UUID, deviceID: UUID, expiresAt: Date, payload: Data) {
        self.id = id
        self.kind = kind
        self.macID = macID
        self.deviceID = deviceID
        self.expiresAt = expiresAt
        self.payload = payload
    }
}

/// A pairing ended from one side: the other side deletes the key and the records.
public struct Revocation: Codable, Sendable, Equatable {
    /// The Mac of the pair.
    public let macID: UUID
    /// The iPhone of the pair.
    public let deviceID: UUID

    /// Creates the revocation of the pair `macID`–`deviceID`.
    public init(macID: UUID, deviceID: UUID) {
        self.macID = macID
        self.deviceID = deviceID
    }
}
