import Foundation
import Testing
@testable import Bubo

@MainActor
struct MemoryLineTests {
    /// The memory folder of a Progetto, under a temporary folder of its own.
    let directory: URL

    init() throws {
        directory = URL(filePath: TrustGate.realPath(FileManager.default.temporaryDirectory.path))
            .appending(path: "MemoryLineTests-\(UUID().uuidString)/projects/-repo/memory", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { directory.appending(path: name) }

    func write(_ text: String, to name: String) throws {
        try Data(text.utf8).write(to: file(name))
    }

    func read(_ name: String) -> String? { try? String(contentsOf: file(name), encoding: .utf8) }

    static func decode(_ line: String) throws -> BridgeEvent {
        try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8))
    }

    // MARK: Lines from the bridge

    @Test func aWriteInTheMemoryBecomesRicordatoWithTheFileBeforeAndAfter() throws {
        let event = try Self.decode(#"{"v":4,"type":"remembered","id":"a1","file":"/m/MEMORY.md","before":"- a\n","after":"- a\n- b\n"}"#)
        #expect(event == .progress(id: "a1", .memory(.remembered(
            MemoryWrite(file: "/m/MEMORY.md", previous: "- a\n", written: "- a\n- b\n")))))
    }

    @Test func aNewFileHasNoBeforeAndATooLargeOneNeither() throws {
        #expect(try Self.decode(#"{"v":4,"type":"remembered","id":"a1","file":"/m/a.md","after":"x"}"#)
            == .progress(id: "a1", .memory(.remembered(MemoryWrite(file: "/m/a.md", previous: nil, written: "x")))))
        #expect(try Self.decode(#"{"v":4,"type":"remembered","id":"a1","file":"/m/a.md"}"#)
            == .progress(id: "a1", .memory(.remembered(MemoryWrite(file: "/m/a.md", previous: nil, written: nil)))))
    }

    @Test func aMemoryRecallBecomesRichiamato() throws {
        let event = try Self.decode(#"""
            {"v":4,"type":"recalled","id":"a1","mode":"select","memories":[{"path":"/m/a.md","scope":"personal"},{"path":"https://org/x","scope":"organization","content":"testo"}]}
            """#)
        #expect(event == .progress(id: "a1", .memory(.recalled(MemoryRecall(isSynthesis: false, memories: [
            .init(path: "/m/a.md", scope: "personal", content: nil),
            .init(path: "https://org/x", scope: "organization", content: "testo"),
        ])))))
    }

    @Test func aSearchCarriesTheConversationThatCalledIt() throws {
        #expect(try Self.decode(#"{"v":4,"type":"search","id":"s1","query":"ci","conversation":"a1"}"#)
            == .search(id: "s1", query: "ci", project: nil, conversation: "a1"))
    }

    @Test func aSearchOfASessioneReachesItsProgressWithWhatItFound() async throws {
        let bridge = AgentBridgeTests.bridge(AgentBridgeTests.answering(#"""
            echo "{\"v\":4,\"type\":\"search\",\"id\":\"s1\",\"query\":\"notarizzazione\",\"conversation\":\"$id\"}"
            read found
            echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
            read _
            """#))
        var received: [AgentProgress] = []
        _ = try await AgentBridgeTests.collect(bridge.ask("x", in: URL(filePath: "/tmp")) { received.append($0) })
        #expect(received == [.memory(.searched(query: "notarizzazione", result: "notarizzazione in tutto"))])
    }

    // MARK: The Sessione's lines

    @Test func aSessioneKeepsItsLatestThreeLinesTheLatestLast() {
        var session = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"))
        for query in ["a", "b", "c", "d"] {
            session.apply(.memory(.searched(query: query, result: "")))
        }
        #expect(session.memoryLines.map(\.subject) == ["b", "c", "d"].map { String(localized: "dall'Indice: «\($0)»") })
    }

    @Test func aSessioneSavedBeforeTheLinesHasNone() throws {
        let saved = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Prova","project":"file:///tmp/","activity":"ferma"}"#
        let session = try JSONDecoder().decode(Session.self, from: Data(saved.utf8))
        #expect(session.memoryLines.isEmpty)
    }

    @Test func theLinesSurviveASave() throws {
        var session = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"))
        session.apply(.memory(.remembered(MemoryWrite(file: "/m/a.md", previous: nil, written: "x"))))
        let saved = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session))
        #expect(saved.memoryLines == session.memoryLines)
    }

    @Test func aLineNamesTheMemoryByItsFrontmatterNameElseByItsFile() {
        let named = MemoryLine(event: .remembered(MemoryWrite(file: "/m/feedback_test.md", previous: nil,
                                                              written: "---\nname: Usa Swift Testing\n---\ncorpo")))
        let plain = MemoryLine(event: .remembered(MemoryWrite(file: "/m/MEMORY.md", previous: nil, written: nil)))
        let recalled = MemoryLine(event: .recalled(MemoryRecall(isSynthesis: false, memories: [
            .init(path: "/m/a.md", scope: "personal", content: nil), .init(path: "/m/b.md", scope: "personal", content: nil),
        ])))
        #expect(named.subject == "Usa Swift Testing")
        #expect(plain.subject == "MEMORY.md")
        #expect(recalled.subject == String(localized: "\(2) ricordi"))
        #expect(!plain.canUndo)
    }

    @Test func apriShowsTheRecalledMemoriesFromTheirFilesOrTheirText() async throws {
        try write("ricordo a", to: "a.md")
        let line = MemoryLine(event: .recalled(MemoryRecall(isSynthesis: false, memories: [
            .init(path: file("a.md").path, scope: "personal", content: nil),
            .init(path: "https://org/x", scope: "organization", content: "ricordo x"),
        ])))
        #expect(await MemoryLine.contents(of: line) == "a.md\n\nricordo a\n\n———\n\nhttps://org/x\n\nricordo x")
    }

    // MARK: Annulla

    @Test func annullaPutsBackTheFileAsItWasBeforeTheWrite() throws {
        try write("- a\n- b\n", to: "MEMORY.md")
        try MemoryWrite(file: file("MEMORY.md").path, previous: "- a\n", written: "- a\n- b\n").undo(in: directory)
        #expect(read("MEMORY.md") == "- a\n")
    }

    @Test func annullaOfANewFileRemovesIt() throws {
        try write("x", to: "a.md")
        try MemoryWrite(file: file("a.md").path, previous: nil, written: "x").undo(in: directory)
        #expect(!FileManager.default.fileExists(atPath: file("a.md").path))
    }

    @Test func annullaLeavesALaterWriteAlone() throws {
        try write("- c\n", to: "MEMORY.md")
        #expect(throws: ProjectMemoryError.changedOnDisk) {
            try MemoryWrite(file: file("MEMORY.md").path, previous: "- a\n", written: "- a\n- b\n").undo(in: directory)
        }
        #expect(read("MEMORY.md") == "- c\n")
    }

    @Test func annullaNeverWritesOutsideTheProgettosMemory() throws {
        let outside = directory.deletingLastPathComponent().appending(path: "a.md")
        try Data("x".utf8).write(to: outside)
        #expect(throws: ProjectMemoryError.outsideMemory) {
            try MemoryWrite(file: outside.path, previous: "prima", written: "x").undo(in: directory)
        }
        #expect(throws: ProjectMemoryError.outsideMemory) {
            try MemoryWrite(file: self.file("../a.md").path, previous: "prima", written: "x").undo(in: directory)
        }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "x")
    }
}
