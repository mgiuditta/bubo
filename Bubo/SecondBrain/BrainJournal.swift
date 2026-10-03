import Foundation

/// The diario of Bubo's writes in the Secondo cervello, on this Mac only: the latest ones, newest first.
nonisolated struct BrainJournal: Sendable {
    /// How many writes the diario keeps: the oldest go first.
    static let capacity = 50

    /// The diario in `Application Support/Bubo/brain-journal`.
    static let standard = BrainJournal(file: URL.applicationSupportDirectory
        .appending(path: "Bubo/brain-journal/changes.json"))

    /// The diario's file.
    let file: URL

    /// The writes kept, newest first; none when the file is missing or unreadable.
    func changes() -> [BrainChange] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([BrainChange].self, from: $0) } ?? []
    }

    /// Adds `change` first, letting the oldest go past ``capacity``.
    ///
    /// - Returns: The writes kept, newest first.
    @discardableResult
    func record(_ change: BrainChange) throws -> [BrainChange] {
        try save(Array(([change] + changes()).prefix(Self.capacity)))
    }

    /// Marks the write `id` as undone.
    ///
    /// - Returns: The writes kept, newest first.
    @discardableResult
    func markUndone(_ id: BrainChange.ID) throws -> [BrainChange] {
        var changes = changes()
        guard let index = changes.firstIndex(where: { $0.id == id }) else { return changes }
        changes[index].isUndone = true
        return try save(changes)
    }

    private func save(_ changes: [BrainChange]) throws -> [BrainChange] {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(changes).write(to: file, options: .atomic)
        return changes
    }
}
