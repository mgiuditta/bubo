import Foundation

/// What an iPhone reads of one Mac: its Battito and the cards of its Sessioni.
public struct MacSnapshot: Sendable, Equatable {
    /// The latest Battito; `nil` before the first.
    public var heartbeat: Heartbeat?
    /// The cards of the Sessioni the Mac lets out, in no order.
    public var cards: [SessionCard]

    /// Creates a snapshot.
    public init(heartbeat: Heartbeat? = nil, cards: [SessionCard] = []) {
        self.heartbeat = heartbeat
        self.cards = cards
    }
}

extension RemoteChannel {
    /// Reads and opens the Battito and the cards the Mac `macID` wrote for the iPhone `deviceID`.
    ///
    /// A record that does not open, such as one from a newer protocol or sealed with an old key, is left out.
    public func snapshot(macID: UUID, deviceID: UUID, sealer: RecordSealer) async throws -> MacSnapshot {
        var snapshot = MacSnapshot()
        for record in try await records(macID: macID, deviceID: deviceID) {
            switch record.kind {
            case .heartbeat:
                guard let heartbeat = try? sealer.open(Heartbeat.self, from: record.payload, recordID: record.id)
                else { continue }
                if heartbeat.sentAt > snapshot.heartbeat?.sentAt ?? .distantPast { snapshot.heartbeat = heartbeat }
            case .sessionCard:
                if let card = try? sealer.open(SessionCard.self, from: record.payload, recordID: record.id) {
                    snapshot.cards.append(card)
                }
            case .request, .verdict, .command:
                continue
            }
        }
        return snapshot
    }
}
