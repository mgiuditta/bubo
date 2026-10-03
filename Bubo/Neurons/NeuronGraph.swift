import Foundation

/// The notes of the Secondo cervello and the links between them, as the Neuroni draw them.
nonisolated struct NeuronGraph: Equatable, Sendable {
    /// A note: one node of the graph.
    struct Note: Equatable, Sendable {
        /// The note's path from the top of the Secondo cervello.
        var path: String
        /// How many other notes it links to or is linked from.
        var degree = 0

        /// The note's name, without `.md`.
        var name: String {
            let file = path.split(separator: "/").last.map(String.init) ?? path
            return file.lowercased().hasSuffix(".md") ? String(file.dropLast(3)) : file
        }

        /// The top folder the note is in; empty for a note at the top.
        var folder: String {
            path.contains("/") ? String(path.split(separator: "/")[0]) : ""
        }

        /// The folder the note is in, as the list shows it under its name; empty at the top.
        var parent: String {
            path.split(separator: "/").dropLast().joined(separator: "/")
        }
    }

    /// The notes, in path order.
    private(set) var notes: [Note] = []
    /// Each pair of linked notes once, by index in ``notes``, the smaller index first.
    private(set) var edges: [SIMD2<UInt32>] = []

    /// Creates the graph of the notes in `links`, by path from the top of the Secondo cervello, each with the links it
    /// has; a link to a note that is not there is left out.
    init(links: [String: [NoteLink]]) {
        let paths = links.keys.sorted()
        notes = paths.map { Note(path: $0) }
        let resolver = NoteLinkResolver(paths: paths)
        var pairs: Set<SIMD2<UInt32>> = []
        for (source, path) in paths.enumerated() {
            for link in links[path] ?? [] {
                guard let target = resolver.note(linkedBy: link, from: path), target != source else { continue }
                pairs.insert(SIMD2(UInt32(min(source, target)), UInt32(max(source, target))))
            }
        }
        edges = pairs.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        for edge in edges {
            notes[Int(edge.x)].degree += 1
            notes[Int(edge.y)].degree += 1
        }
    }

    /// The top folders of the notes, in name order, the top itself first when a note is there.
    var folders: [String] {
        Set(notes.map(\.folder)).sorted()
    }
}
