import CoreServices
import Foundation
import Testing
@testable import Bubo

/// A `~/.claude` and an Indice in a temporary folder, deleted with the value.
final class ClaudeFolder {
    let folder = URL.temporaryDirectory.appending(path: "SearchIndexTests-\(UUID().uuidString)")
    var root: URL { folder.appending(path: "claude") }
    var database: URL { folder.appending(path: "indice/indice.sqlite") }

    init() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "projects"), withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    func write(_ text: String, to path: String) throws {
        let file = root.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func open() throws -> SearchIndex {
        try SearchIndex(database: database, root: root)
    }

    /// The real path FSEvents reports, with `/private` in front of the temporary folder.
    func resolved(_ path: String) -> String {
        let real = realpath(root.path, nil)!
        defer { free(real) }
        return String(cString: real) + "/" + path
    }
}

@Suite(.timeLimit(.minutes(1)))
struct SearchIndexTests {
    let claude: ClaudeFolder

    init() throws {
        claude = try ClaudeFolder()
    }

    @Test func memoryAndTheUsersClaudeMdAreFoundByWord() async throws {
        try claude.write("# Rilascio\n\nLa notarizzazione passa da notarytool.", to: "projects/-Users-a-bubo/memory/rilascio.md")
        try claude.write("Rispondi sempre in italiano.", to: "CLAUDE.md")
        let index = try claude.open()
        await index.rescan()

        let hits = try await index.hits(for: "notarizzazione")
        #expect(hits.map(\.project) == ["-Users-a-bubo"])
        #expect(hits.first?.text.contains("notarytool") == true)
        #expect(try await index.hits(for: "italiano").map(\.project) == [nil])
    }

    @Test func projectCodeAndTranscriptsStayOut() async throws {
        try claude.write("segreto nel codice", to: "projects/-Users-a-bubo/main.md")
        try claude.write(#"{"segreto":"nel transcript"}"#, to: "projects/-Users-a-bubo/abc.jsonl")
        try claude.write("segreto in un file di testo", to: "projects/-Users-a-bubo/memory/note.txt")
        let index = try claude.open()
        await index.rescan()

        #expect(try await index.hits(for: "segreto").isEmpty)
    }

    @Test func aRescanFollowsEditsAndDeletions() async throws {
        try claude.write("vecchia parola", to: "projects/-p/memory/a.md")
        try claude.write("da cancellare", to: "projects/-p/memory/b.md")
        let index = try claude.open()
        await index.rescan()

        try claude.write("nuova parola, più lunga", to: "projects/-p/memory/a.md")
        try FileManager.default.removeItem(at: claude.root.appending(path: "projects/-p/memory/b.md"))
        await index.rescan()

        #expect(try await index.hits(for: "vecchia").isEmpty)
        #expect(try await index.hits(for: "nuova").count == 1)
        #expect(try await index.hits(for: "cancellare").isEmpty)
    }

    @Test func aProjectFolderLimitsTheSearchToItsMemory() async throws {
        try claude.write("deploy con fastlane", to: "projects/-Users-a-bubo/memory/a.md")
        try claude.write("deploy con kubectl", to: "projects/-Users-a-altro/memory/a.md")
        let index = try claude.open()
        await index.rescan()

        let hits = try await index.hits(for: "deploy", project: "/Users/a/bubo")
        #expect(hits.map(\.project) == ["-Users-a-bubo"])
    }

    @Test(arguments: ["\"", "AND OR NOT", "a*b(c", "NEAR(x y)", "  "])
    func queryTextIsNeverFts5Syntax(text: String) async throws {
        try claude.write("AND testo qualsiasi", to: "projects/-p/memory/a.md")
        let index = try claude.open()
        await index.rescan()

        _ = try await index.hits(for: text)
    }

    @Test func accentsDoNotMatter() async throws {
        try claude.write("La città è grande", to: "projects/-p/memory/a.md")
        let index = try claude.open()
        await index.rescan()

        #expect(try await index.hits(for: "citta").count == 1)
    }

    @Test func anEmptyResultSaysSo() async throws {
        let index = try claude.open()
        #expect(await index.toolResult(for: "nulla", project: nil) == "Nessun risultato nell'Indice.")
    }

    @Test func projectNamesMatchClaudeCode() {
        #expect(SearchIndex.projectName(ofFolder: "/Users/mgiuditta/Dev/bubo") == "-Users-mgiuditta-Dev-bubo")
        #expect(SearchIndex.projectName(ofFolder: "/a/my_app.v2") == "-a-my-app-v2")
    }

    @Test func markdownSplitsAtHeadingsButNotInsideCode() {
        let fragments = MarkdownFragments.split("intro\n# Uno\ntesto\n```\n# non titolo\n```\n## Due\naltro\n#tag")
        #expect(fragments == ["intro", "# Uno\ntesto\n```\n# non titolo\n```", "## Due\naltro\n#tag"])
    }

    // MARK: Freshness, against real FSEvents

    /// Waits up to five seconds for `text` to become findable.
    func waitUntilFound(_ text: String, in index: SearchIndex) async throws -> Bool {
        for _ in 0..<50 {
            if try await !index.hits(for: text).isEmpty { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    @Test func aSavedNoteIsFoundWithinFiveSeconds() async throws {
        let index = try claude.open()
        let fresh = Task { await index.keepFresh() }
        defer { fresh.cancel() }
        try await Task.sleep(for: .milliseconds(300))

        try claude.write("appena salvata: ornitorinco", to: "projects/-p/memory/nuova.md")

        #expect(try await waitUntilFound("ornitorinco", in: index))
    }

    @Test func aChangeMadeWhileClosedIsFoundAfterRestart() async throws {
        try claude.write("prima", to: "projects/-p/memory/a.md")
        let first = try claude.open()
        let fresh = Task { await first.keepFresh() }
        try await Task.sleep(for: .milliseconds(500))
        fresh.cancel()
        _ = await fresh.value

        // Bubo closed: an edit no stream sees.
        try claude.write("scritta a Bubo chiuso: lontra", to: "projects/-p/memory/a.md")
        try await Task.sleep(for: .seconds(1))

        let reopened = try claude.open()
        let again = Task { await reopened.keepFresh() }
        defer { again.cancel() }
        #expect(try await waitUntilFound("lontra", in: reopened))
    }

    @Test func eventsAreReplayedFromTheSavedEventID() async throws {
        let since = FSEventsGetCurrentEventId()
        try await Task.sleep(for: .milliseconds(200))
        try claude.write("x", to: "projects/-p/memory/a.md")
        try await Task.sleep(for: .seconds(1))

        let path = claude.resolved("projects/-p/memory/a.md")
        for await batch in FileEvents.batches(under: String(claude.resolved("").dropLast()), since: since, latency: 0.1)
            where batch.paths.contains(path) {
            #expect(batch.latestID > since)
            break
        }
    }

    @Test(arguments: [kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagKernelDropped,
                      kFSEventStreamEventFlagUserDropped, kFSEventStreamEventFlagEventIdsWrapped,
                      kFSEventStreamEventFlagRootChanged])
    func lostEventsCallForARescan(flag: Int) {
        #expect(FileEvents.rescanFlags & FSEventStreamEventFlags(flag) != 0)
    }
}
