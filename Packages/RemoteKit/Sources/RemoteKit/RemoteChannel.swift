import Foundation

/// Where the Mac and the iPhone exchange pairing responses, records and revocations.
///
/// In the product it is the private CloudKit database (ADR 0007); ``InMemoryRemoteChannel`` stands in for it in
/// tests and until the CloudKit container exists (#244).
public protocol RemoteChannel: Sendable {
    /// Sends the iPhone's answer to a QR.
    func send(_ response: PairingResponse) async throws
    /// The answers to the invitation `invitationID`, including those already sent.
    func responses(to invitationID: UUID) async -> AsyncStream<PairingResponse>
    /// Saves a record, replacing one with the same ID.
    func save(_ record: RemoteRecord) async throws
    /// The records of the pair `macID`–`deviceID`.
    func records(macID: UUID, deviceID: UUID) async throws -> [RemoteRecord]
    /// Deletes the records `ids`; an ID with no record is not an error.
    func deleteRecords(_ ids: [String]) async throws
    /// Deletes every record of the Mac `macID` that expires before `date`, for every iPhone.
    func deleteRecords(of macID: UUID, expiringBefore date: Date) async throws
    /// Marks the pair revoked and deletes all its records.
    func revoke(_ revocation: Revocation) async throws
    /// Every revocation, by either side, including those sent before listening: a revoked Device stays revoked.
    func revocations() async -> AsyncStream<Revocation>
}

/// A ``RemoteChannel`` in memory, within one process.
public actor InMemoryRemoteChannel: RemoteChannel {
    private var sentResponses: [PairingResponse] = []
    private var responseListeners: [UUID: [AsyncStream<PairingResponse>.Continuation]] = [:]
    private var storedRecords: [String: RemoteRecord] = [:]
    private var revocationListeners: [AsyncStream<Revocation>.Continuation] = []
    /// Every revocation received, in order.
    public private(set) var revoked: [Revocation] = []

    /// Creates an empty channel.
    public init() {}

    public func send(_ response: PairingResponse) {
        sentResponses.append(response)
        for listener in responseListeners[response.invitationID] ?? [] {
            listener.yield(response)
        }
    }

    public func responses(to invitationID: UUID) -> AsyncStream<PairingResponse> {
        let (stream, continuation) = AsyncStream.makeStream(of: PairingResponse.self)
        for response in sentResponses where response.invitationID == invitationID {
            continuation.yield(response)
        }
        responseListeners[invitationID, default: []].append(continuation)
        return stream
    }

    public func save(_ record: RemoteRecord) {
        storedRecords[record.id] = record
    }

    public func records(macID: UUID, deviceID: UUID) -> [RemoteRecord] {
        storedRecords.values.filter { $0.macID == macID && $0.deviceID == deviceID }
    }

    public func deleteRecords(_ ids: [String]) {
        for id in ids { storedRecords[id] = nil }
    }

    public func deleteRecords(of macID: UUID, expiringBefore date: Date) {
        storedRecords = storedRecords.filter { $0.value.macID != macID || $0.value.expiresAt >= date }
    }

    public func revoke(_ revocation: Revocation) {
        storedRecords = storedRecords.filter {
            $0.value.macID != revocation.macID || $0.value.deviceID != revocation.deviceID
        }
        revoked.append(revocation)
        for listener in revocationListeners {
            listener.yield(revocation)
        }
    }

    public func revocations() -> AsyncStream<Revocation> {
        let (stream, continuation) = AsyncStream.makeStream(of: Revocation.self)
        for revocation in revoked {
            continuation.yield(revocation)
        }
        revocationListeners.append(continuation)
        return stream
    }
}
