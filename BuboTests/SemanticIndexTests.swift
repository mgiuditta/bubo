import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import Bubo

/// An embedder that knows a few topics: a text becomes how often it names each, so synonyms land together.
nonisolated final class TopicEmbedder: TextEmbedder {
    init(id: String = "argomenti", topics: [[String]] = TopicEmbedder.topics) {
        model = TextEmbeddingModel(id: id, name: id, repository: "", revision: "1", files: [], queryPrefix: "",
                                   passagePrefix: "", maximumTokens: 512)
        self.topics = topics
    }

    static let topics = [["gatto", "micio", "felino"], ["auto", "macchina", "tagliando"],
                         ["pioggia", "temporale", "maltempo"]]

    let model: TextEmbeddingModel
    let topics: [[String]]
    let queries = Mutex(0)

    func vectors(for texts: [String], as role: EmbeddingRole) async throws -> [[Float]] {
        if role == .query { queries.withLock { $0 += 1 } }
        return texts.map { text in
            let words = text.lowercased().split { !$0.isLetter }
            // A last component, so a text naming no topic still has a direction.
            var vector = topics.map { topic in Float(words.count { topic.contains(String($0)) }) } + [0.1]
            let length = sqrt(vector.reduce(0) { $0 + $1 * $1 })
            for index in vector.indices { vector[index] /= length }
            return vector
        }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct SemanticIndexTests {
    let claude: ClaudeFolder

    init() throws {
        claude = try ClaudeFolder()
    }

    /// An Indice over `notes`, one memory file each, searching by meaning with `embedder`.
    func index(of notes: [String: String], embedder: TopicEmbedder = TopicEmbedder()) async throws -> SearchIndex {
        for (name, text) in notes {
            try claude.write(text, to: "projects/-p/memory/\(name).md")
        }
        let index = try claude.open()
        await index.use(embedder)
        await index.rescan()
        await index.vectorsComputed()
        return index
    }

    @Test func aNoteIsFoundByMeaningWithoutWordsInCommon() async throws {
        let index = try await index(of: ["gatto": "Il micio dorme sul divano."])

        let hits = try await index.hits(for: "felino")

        #expect(hits.map(\.text) == ["Il micio dorme sul divano."])
    }

    @Test func withoutAModelOnlyWordsCount() async throws {
        try claude.write("Il micio dorme sul divano.", to: "projects/-p/memory/gatto.md")
        let index = try claude.open()
        await index.rescan()

        #expect(try await index.hits(for: "felino").isEmpty)
        #expect(try await index.hits(for: "micio").map(\.match) == [.words])
        #expect(await index.vectorCount == 0)
        #expect(await !index.searchesByMeaning)
    }

    /// The Palette underlines what only the meaning found, and highlights the words of the rest.
    @Test func eachHitSaysWhichRankingsFoundIt() async throws {
        let index = try await index(of: ["parola": "Il tagliando del felino? No, della bicicletta.",
                                         "senso": "Portare la macchina dal meccanico."])

        let hits = try await index.hits(for: "tagliando", limit: 2)

        #expect(hits.map(\.match) == [[.words, .meaning], .meaning])
        #expect(hits.map(\.isFoundByMeaningOnly) == [false, true])
        #expect(await index.searchesByMeaning)
    }

    @Test func wordsAndMeaningAreFusedWithTheBothFirst() async throws {
        let index = try await index(of: ["parola": "Il tagliando del felino? No, della bicicletta.",
                                         "senso": "Portare la macchina dal meccanico.",
                                         "altro": "Ricetta della carbonara."])

        let hits = try await index.hits(for: "tagliando", limit: 2)

        // In both rankings first, then the one found only by meaning.
        #expect(hits.map(\.path.lastPathComponent) == ["parola.md", "senso.md"])
    }

    @Test func oneWordInCommonDoesNotOutrankTheMeaning() async throws {
        let index = try await index(of: ["parola": "La casa al mare.", "senso": "Il gatto dorme."])

        // Four words that carry meaning: a word match needs two of them, and "casa" alone is not enough.
        let hits = try await index.hits(for: "un felino in casa nostra oggi", limit: 1)

        #expect(hits.map(\.text) == ["Il gatto dorme."])
    }

    @Test func editedAndDeletedNotesForgetTheirVectors() async throws {
        let index = try await index(of: ["a": "Il gatto.", "b": "La macchina."])
        #expect(await index.vectorCount == 2)

        try FileManager.default.removeItem(at: claude.root.appending(path: "projects/-p/memory/b.md"))
        try claude.write("Il micio, più lungo di prima.", to: "projects/-p/memory/a.md")
        await index.rescan()
        await index.vectorsComputed()

        #expect(await index.vectorCount == 1)
        #expect(try await index.hits(for: "automobile macchina").allSatisfy { !$0.text.contains("La macchina") })
    }

    @Test func anotherModelComputesEveryVectorAgain() async throws {
        let index = try await index(of: ["a": "Il gatto.", "b": "La macchina."])
        let other = TopicEmbedder(id: "altro", topics: [["gatto"]])

        await index.use(other)
        await index.vectorsComputed()

        #expect(await index.vectorCount == 2)
        #expect(try await index.hits(for: "gatto").first?.text == "Il gatto.")
    }

    @Test func vectorsSurviveAReopening() async throws {
        let embedder = TopicEmbedder()
        _ = try await index(of: ["a": "Il gatto."], embedder: embedder)

        let reopened = try claude.open()
        await reopened.use(embedder)
        await reopened.vectorsComputed()

        #expect(await reopened.vectorCount == 1)
        #expect(try await reopened.hits(for: "felino").count == 1)
    }

    @Test func aProjectFolderLimitsTheSearchByMeaningToo() async throws {
        try claude.write("Il micio di bubo.", to: "projects/-Users-a-bubo/memory/a.md")
        try claude.write("Il gatto di un altro.", to: "projects/-Users-a-altro/memory/a.md")
        let index = try claude.open()
        await index.use(TopicEmbedder())
        await index.rescan()
        await index.vectorsComputed()

        let hits = try await index.hits(for: "felino", project: "/Users/a/bubo")

        #expect(hits.map(\.project) == ["-Users-a-bubo"])
    }

    @Test func aFailingModelFallsBackToWords() async throws {
        let index = try await index(of: ["a": "Il gatto nero."])
        await index.use(FailingEmbedder())

        #expect(try await index.hits(for: "gatto").count == 1)
    }

    @Test func aPastConversationIsFoundByMeaningPieceByPiece() async throws {
        let index = try claude.open()
        await index.use(TopicEmbedder())
        let long = String(repeating: "Ricetta senza ingredienti. ", count: 80) + "\n\nIl micio dorme."
        try await index.store([CLIConversation.Message(id: "m1", isFromUser: true, text: long, date: nil)],
                              ofConversation: "c1", in: nil, modified: .now)
        await index.vectorsComputed()

        let hits = try await index.hits(for: "felino", limit: 1)

        #expect(await index.vectorCount == 2)
        #expect(hits.first?.text.hasSuffix("Il micio dorme.") == true)
        #expect(hits.first?.message?.id == "m1")
    }

    // MARK: Fragments an embedding model can read whole

    @Test func aLongSectionIsCutIntoPiecesThatKeepItsHeading() {
        let paragraph = String(repeating: "parola ", count: 100)  // 700 characters
        let section = "## Viaggio\n" + Array(repeating: paragraph, count: 5).joined(separator: "\n\n")

        let pieces = MarkdownFragments.split(section)

        #expect(pieces.count == 3)
        #expect(pieces.allSatisfy { $0.count <= MarkdownFragments.maximumLength && $0.hasPrefix("## Viaggio\n") })
        #expect(pieces.joined().components(separatedBy: "parola").count - 1 == 500)
    }

    @Test func aLongLineIsCutAtWords() {
        let pieces = MarkdownFragments.pieces(of: String(repeating: "abc ", count: 1000), maximumLength: 100)

        #expect(pieces.allSatisfy { $0.count <= 100 })
        #expect(pieces.joined(separator: " ").split(separator: " ").count == 1000)
    }

    @Test func aShortSectionStaysWhole() {
        #expect(MarkdownFragments.pieces(of: "# Breve\ntesto") == ["# Breve\ntesto"])
    }

    // MARK: Vectors in memory

    @Test func theNearestVectorsComeFirst() {
        var matrix = VectorMatrix(dimension: 2)
        matrix.insert(VectorMatrix.half([1, 0]), for: 10)
        matrix.insert(VectorMatrix.half([0, 1]), for: 20)
        matrix.insert(VectorMatrix.half([0.7, 0.7]), for: 30)

        #expect(matrix.nearest(to: [1, 0], limit: 2) == [10, 30])
        #expect(matrix.nearest(to: [1, 0], limit: 5, allowed: [20, 30]) == [30, 20])
    }

    @Test func removingAVectorKeepsTheOthersInPlace() {
        var matrix = VectorMatrix(dimension: 2)
        matrix.insert(VectorMatrix.half([1, 0]), for: 1)
        matrix.insert(VectorMatrix.half([0, 1]), for: 2)
        matrix.insert(VectorMatrix.half([-1, 0]), for: 3)

        matrix.remove(1)
        matrix.insert(VectorMatrix.half([0, -1]), for: 2)

        #expect(matrix.count == 2)
        #expect(matrix.nearest(to: [-1, 0], limit: 1) == [3])
        #expect(matrix.nearest(to: [0, -1], limit: 1) == [2])
    }

    @Test func fusionRewardsWhatBothRankingsFound() {
        let fused = ReciprocalRankFusion.fuse([["a", "b", "c"], ["c", "d", "b"]])
        #expect(fused == ["c", "b", "a", "d"])
    }

    /// The spec's budget: ≤ 50 ms p95 from the query to the results with 30.000 fragments.
    /// The embedding of the query is measured with the real model, in ``RealModelTests``.
    @Test func aSearchOf30000FragmentsStaysWithinBudget() {
        var generator = SystemRandomNumberGenerator()
        var matrix = VectorMatrix(dimension: 384)
        func randomVector() -> [Float] {
            let vector = (0..<384).map { _ in Float.random(in: -1...1, using: &generator) }
            let length = sqrt(vector.reduce(0) { $0 + $1 * $1 })
            return vector.map { $0 / length }
        }
        for rowID in 0..<30_000 {
            matrix.insert(VectorMatrix.half(randomVector()), for: Int64(rowID))
        }
        let words = (0..<50).map { Int64($0 * 7) }
        var durations: [Duration] = []
        for _ in 0..<40 {
            let query = randomVector()
            let started = ContinuousClock.now
            _ = ReciprocalRankFusion.fuse([words, matrix.nearest(to: query, limit: 50)]).prefix(8)
            durations.append(ContinuousClock.now - started)
        }
        let p95 = durations.sorted()[Int(Double(durations.count) * 0.95) - 1]
        #expect(p95 < .milliseconds(50), "p95 \(p95)")
    }
}

/// An embedder of the same model as ``TopicEmbedder`` that always fails, as a model whose files went missing.
nonisolated final class FailingEmbedder: TextEmbedder {
    let model = TopicEmbedder().model

    func vectors(for texts: [String], as role: EmbeddingRole) async throws -> [[Float]] {
        throw CancellationError()
    }
}

private extension String {
    var lastPathComponent: String { (self as NSString).lastPathComponent }
}
