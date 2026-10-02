import Foundation

/// What an iPhone reads of one Mac: its Battito, the cards of its Sessioni and the Richieste waiting.
public struct MacSnapshot: Sendable, Equatable {
    /// The latest Battito; `nil` before the first.
    public var heartbeat: Heartbeat?
    /// The cards of the Sessioni the Mac lets out, in no order.
    public var cards: [SessionCard]
    /// The Richieste di permesso still open on the Mac, in no order.
    public var requests: [RemoteRequest]

    /// Creates a snapshot.
    public init(heartbeat: Heartbeat? = nil, cards: [SessionCard] = [], requests: [RemoteRequest] = []) {
        self.heartbeat = heartbeat
        self.cards = cards
        self.requests = requests
    }
}

extension RemoteChannel {
    /// Reads and opens the Battito, the cards and the open Richieste the Mac `macID` wrote for the iPhone `deviceID`.
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
            case .request:
                if let request = try? sealer.open(RemoteRequest.self, from: record.payload, recordID: record.id),
                   !request.isResolved {
                    snapshot.requests.append(request)
                }
            case .verdict, .command:
                continue
            }
        }
        return snapshot
    }
}
