import Foundation
import os

/// The links and the place of each note of a Secondo cervello, kept in Bubo's Caches folder: a note is read again only
/// when its ``FileStamp`` changes, and the graph opens with the shape it had.
nonisolated struct NeuronCache: Sendable {
    /// What is kept of one note.
    struct Entry: Codable, Equatable, Sendable {
        var size: Int
        var modified: Double
        var links: [NoteLink]
        var x: Float?
        var y: Float?

        /// The note's place on the plane; `nil` before its first layout.
        var position: SIMD2<Float>? {
            guard let x, let y else { return nil }
            return SIMD2(x, y)
        }

        /// Whether the note was saved with `stamp`, so its links need no new reading.
        func matches(_ stamp: FileStamp) -> Bool {
            size == stamp.size && modified == stamp.modified
        }
    }

    /// The folder of the saved files.
    var folder: URL

    /// The cache in Bubo's Caches folder.
    static let standard = NeuronCache(folder: URL.cachesDirectory.appending(path: "com.mgiuditta.bubo/Neuroni",
                                                                            directoryHint: .isDirectory))

    /// The notes last saved for the Secondo cervello at `secondBrain`, by path from its top; empty when there are none.
    func entries(of secondBrain: String) -> [String: Entry] {
        guard let data = try? Data(contentsOf: file(for: secondBrain)) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    /// Saves `entries` for the Secondo cervello at `secondBrain`, replacing what was there.
    func save(_ entries: [String: Entry], of secondBrain: String) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file(for: secondBrain), options: .atomic)
        } catch {
            Logger.neurons.error("Neuroni: cache not saved: \(error)")
        }
    }

    private func file(for secondBrain: String) -> URL {
        folder.appending(path: String(GalaxyLayout.fnv1a(secondBrain), radix: 16) + ".json")
    }
}

extension Logger {
    nonisolated static let neurons = Logger(subsystem: "com.mgiuditta.bubo", category: "neurons")
}
