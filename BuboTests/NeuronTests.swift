import Foundation
import simd
import Testing
@testable import Bubo

struct NoteLinkTests {
    @Test("Wikilinks lose their alias, section and block, and an embed counts as a link")
    func wikilinks() {
        let links = NoteLink.links(in: "Vedi [[Idee|le idee]], [[Progetti/Bubo#Piano]], [[Diario#^abc]] e ![[Schema]].")
        #expect(links.map(\.target) == ["Idee", "Progetti/Bubo", "Diario", "Schema"])
        #expect(links.allSatisfy { $0.kind == .wikilink })
    }

    @Test("Markdown links to notes are decoded; the web, images and anchors are left out")
    func markdownLinks() {
        let text = """
        [uno](../Archivio/Nota%20uno.md#Titolo) [due](<Altra nota.md>) [tre](Senza%20estensione)
        [web](https://example.com/a.md) [mail](mailto:a@b.c) [qui](#Sezione) ![img](foto.png)
        """
        let links = NoteLink.links(in: text)
        #expect(links == [NoteLink(target: "../Archivio/Nota uno.md", kind: .relative),
                          NoteLink(target: "Altra nota.md", kind: .relative),
                          NoteLink(target: "Senza estensione", kind: .relative)])
    }

    @Test("Links inside code are not links")
    func code() {
        let text = """
        Testo con `[[Finto]]` in linea.
        ```
        [[Nel blocco]]
        ```
        [[Vero]]
        """
        #expect(NoteLink.links(in: text).map(\.target) == ["Vero"])
    }

    @Test("A name goes to the note in the same folder, else to the one nearest to the top")
    func resolvesNames() {
        let resolver = NoteLinkResolver(paths: ["A/Idee.md", "Idee.md", "B/C/Idee.md", "B/Piano.md"])
        #expect(resolver.note(linkedBy: NoteLink(target: "idee", kind: .wikilink), from: "A/Altro.md") == 0)
        #expect(resolver.note(linkedBy: NoteLink(target: "Idee", kind: .wikilink), from: "B/Piano.md") == 1)
        #expect(resolver.note(linkedBy: NoteLink(target: "C/Idee", kind: .wikilink), from: "Idee.md") == 2)
        #expect(resolver.note(linkedBy: NoteLink(target: "Manca", kind: .wikilink), from: "Idee.md") == nil)
    }

    @Test("A relative path goes from the folder of the note that links, and never above the top")
    func resolvesRelativePaths() {
        let resolver = NoteLinkResolver(paths: ["A/Nota uno.md", "B/Piano.md"])
        #expect(resolver.note(linkedBy: NoteLink(target: "../A/Nota uno.md", kind: .relative), from: "B/Piano.md") == 0)
        #expect(resolver.note(linkedBy: NoteLink(target: "B/Piano.md", kind: .relative), from: "A/Nota uno.md") == 1)
        #expect(resolver.note(linkedBy: NoteLink(target: "../../B/Piano.md", kind: .relative), from: "A/Nota uno.md") == nil)
    }
}

struct NeuronGraphTests {
    private let graph = NeuronGraph(links: [
        "Idee.md": [NoteLink(target: "Progetti/Bubo", kind: .wikilink), NoteLink(target: "Manca", kind: .wikilink),
                    NoteLink(target: "Idee", kind: .wikilink)],
        "Progetti/Bubo.md": [NoteLink(target: "../Idee.md", kind: .relative), NoteLink(target: "Diario", kind: .wikilink)],
        "Diario/2026-10-03.md": [],
        "Diario.md": [],
    ])

    @Test("Each pair of linked notes is one edge; missing notes and links to itself are left out")
    func edges() {
        #expect(graph.notes.map(\.path) == ["Diario.md", "Diario/2026-10-03.md", "Idee.md", "Progetti/Bubo.md"])
        #expect(graph.edges == [SIMD2(0, 3), SIMD2(2, 3)])
        #expect(graph.notes.map(\.degree) == [1, 0, 1, 2])
    }

    @Test("Notes know their top folder and their name")
    func folders() {
        #expect(graph.folders == ["", "Diario", "Progetti"])
        #expect(graph.notes[1].name == "2026-10-03")
        #expect(graph.notes[1].folder == "Diario")
    }
}

struct NeuronLayoutTests {
    /// A ring of 40 notes, each linked to the next, and 10 notes linked to nothing.
    private let graph = NeuronGraph(links: Dictionary(uniqueKeysWithValues: (0..<50).map { index in
        ("Note/\(index).md", index < 40 ? [NoteLink(target: "\((index + 1) % 40)", kind: .wikilink)] : [])
    }))

    @Test("The same graph gives the same places")
    func deterministic() {
        #expect(NeuronLayout.positions(of: graph) == NeuronLayout.positions(of: graph))
    }

    @Test("Linked notes end nearer than the notes on average")
    func linkedNotesAreNear() {
        let positions = NeuronLayout.positions(of: graph)
        let linked: [Float] = graph.edges.map { simd_distance(positions[Int($0.x)], positions[Int($0.y)]) }
        var all: [Float] = []
        for a in positions.indices {
            for b in positions.indices where b > a { all.append(simd_distance(positions[a], positions[b])) }
        }
        let linkedMean = linked.reduce(0, +) / Float(linked.count)
        let mean = all.reduce(0, +) / Float(all.count)
        #expect(linkedMean < mean / 2)
        #expect(positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test("Notes already placed stay where they were")
    func keepsPlaced() {
        let first = NeuronLayout.positions(of: graph)
        var placed = Dictionary(uniqueKeysWithValues: zip(graph.notes.map(\.path), first))
        placed["Note/7.md"] = nil
        let second = NeuronLayout.positions(of: graph, keeping: placed)
        for (index, note) in graph.notes.enumerated() where note.path != "Note/7.md" {
            #expect(second[index] == first[index])
        }
    }
}

@MainActor
struct NeuronModelTests {
    @Test("Reading a Secondo cervello builds the graph and caches links and places")
    func readsAndCaches() async throws {
        let folder = URL.temporaryDirectory.appending(path: "Neuroni-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appending(path: "Progetti"), withIntermediateDirectories: true)
        try "Vedi [[Bubo]].".write(to: folder.appending(path: "Idee.md"), atomically: true, encoding: .utf8)
        try "Torna alle [idee](../Idee.md).".write(to: folder.appending(path: "Progetti/Bubo.md"), atomically: true,
                                                  encoding: .utf8)
        let cache = NeuronCache(folder: folder.appending(path: ".cache"))
        let location = SecondBrainLocation(folder: folder)
        let (graph, positions) = await NeuronModel.read(location, cache: cache)
        #expect(graph.notes.map(\.path) == ["Idee.md", "Progetti/Bubo.md"])
        #expect(graph.edges == [SIMD2(0, 1)])
        let saved = cache.entries(of: location.path)
        #expect(saved["Idee.md"]?.position == positions[0])
        let again = await NeuronModel.read(location, cache: cache)
        #expect(again.positions == positions)
    }
}
