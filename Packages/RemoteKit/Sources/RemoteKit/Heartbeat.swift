import Foundation

/// The Battito: the Mac says it is awake and Bubo is open, every 60 s (spec 21).
///
/// Travels only inside the encrypted payload of a ``RemoteRecord`` of kind `heartbeat`, one per Mac and iPhone.
public struct Heartbeat: Codable, Sendable, Equatable {
    /// How old a Battito can be before the iPhone warns that its data may be old.
    public static let freshness: TimeInterval = 120

    /// The Mac's name, as on the pairing QR.
    public let macName: String
    /// When the Mac wrote it.
    public let sentAt: Date
    /// Whether the Mac wrote it on its way to sleep: no other Battito follows until it wakes.
    public let isAsleep: Bool

    /// Creates a Battito written at `sentAt`.
    public init(macName: String, sentAt: Date, isAsleep: Bool = false) {
        self.macName = macName
        self.sentAt = sentAt
        self.isAsleep = isAsleep
    }

    /// Whether the data from the Mac may be old at `date`: the Mac sleeps, or the Battito is over 2 minutes old.
    public func isStale(at date: Date) -> Bool {
        isAsleep || date.timeIntervalSince(sentAt) > Self.freshness
    }
}
