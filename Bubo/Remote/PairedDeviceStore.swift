import Foundation
import RemoteKit

/// Where the Mac keeps its paired iPhones; ``KeychainStore`` in the app.
nonisolated protocol PairedDeviceStore: Sendable {
    /// Every paired iPhone.
    func items() async throws -> [PairedDevice]
    /// Saves `item`, replacing the iPhone with the same ID.
    func save(_ item: PairedDevice) async throws
    /// Forgets the iPhone `id` and its record key; forgetting one that is not there is not an error.
    func delete(id: UUID) async throws
}

extension KeychainStore: PairedDeviceStore where Item == PairedDevice {}
