import Foundation

/// A Marketplace registered in Claude Code.
nonisolated struct Marketplace: Identifiable, Sendable, Equatable {
    /// The name the plugins' identifiers end with.
    let name: String
    /// The clone, or the local folder of a Marketplace added from disk; `nil` when only `claude` knows it.
    var installLocation: URL?

    var id: String { name }
}
