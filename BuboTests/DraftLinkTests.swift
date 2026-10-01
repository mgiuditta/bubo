import Foundation
import Testing
@testable import Bubo

/// `bubo://` links: anyone can write one, so they are checked one by one and make at most a Bozza, never a Sessione;
/// the same issue from ⌘I and from a link is one Bozza or Sessione.
@MainActor
struct DraftLinkTests {
    let folder: URL
    let project: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "DraftLinkTests-\(UUID().uuidString)",
                                                                  directoryHint: .isDirectory)
        project = folder.appending(path: "progetto", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    /// A store with no Sessioni, kept in a temporary file, with its Bozze only in memory.
    func makeStore(sessions: [Session] = []) throws -> SessionStore {
        let file = folder.appending(path: "Sessioni.json")
        try JSONEncoder().encode(sessions).write(to: file)
        return SessionStore(file: file, worktrees: WorktreeManager(root: folder.appending(path: "Worktrees"))) {
            throw CancellationError()
        }
    }

    func linkURL(_ query: String) -> URL {
        URL(string: "bubo://draft?project=\(project.path(percentEncoded: true))&\(query)")!
    }

    @Test func aLinkWrittenByHandGivesTitleAndText() throws {
        let link = try #require(DraftLink(linkURL("title=Esporta%20in%20CSV&text=Dal%20menu%20File&extra=ignorato")))

        #expect(link.project.path == project.standardizedFileURL.path)
        #expect(link.title == "Esporta in CSV")
        #expect(link.text == "Dal menu File")
        #expect(link.issue == nil)
    }

    @Test func aLinkFromAGitHubIssueKeepsOnlyTheIssueAndItsTitle() throws {
        let link = try #require(DraftLink(linkURL("source=github&id=42&title=Login%20rotto&text=fai%20altro")))
        #expect(link.issue == .github(42))
        #expect(link.title == "Login rotto")
        // The issue is read at Avvia: the text of a link is not kept.
        #expect(link.text.isEmpty)

        #expect(DraftLink(linkURL("source=github&id=7"))?.title == "#7")
    }

    @Test(arguments: [
        "https://draft?project=/tmp&title=x",
        "bubo://session?project=/tmp&title=x",
        "bubo://draft/start?project=/tmp&title=x",
        "bubo://draft?title=x",
        "bubo://draft?project=relativo&title=x",
        "bubo://draft?project=/tmp",
        "bubo://draft?project=/tmp&title=%20%20",
        "bubo://draft?project=/tmp&project=/etc&title=x",
        "bubo://draft?project=/tmp&title=x&title=y",
        "bubo://draft?project=/tmp&source=linear&id=ENG-1",
        "bubo://draft?project=/tmp&source=github",
        "bubo://draft?project=/tmp&source=github&id=0",
        "bubo://draft?project=/tmp&source=github&id=-3",
        "bubo://draft?project=/tmp&source=github&id=42abc",
        "bubo://draft?project=/tmp&source=github&id=042",
    ])
    func aLinkThatIsNotValidMakesNothing(url: String) throws {
        #expect(DraftLink(try #require(URL(string: url))) == nil)
    }

    @Test func aLongOrMultilineTitleIsCutToOneLine() throws {
        let long = String(repeating: "a", count: 500)
        let link = try #require(DraftLink(linkURL("title=riga%0Auna%E2%80%AEdue&text=\(long)\(long)\(long)\(long)\(long)\(long)\(long)\(long)\(long)")))
        #expect(link.title == "riga una due")
        #expect(link.text.count == DraftLink.maximumTextLength)
        #expect(try #require(DraftLink(linkURL("title=\(long)"))).title.count == DraftLink.maximumTitleLength)
    }

    @Test func thePathIsStandardised() throws {
        let link = try #require(DraftLink(URL(string: "bubo://draft?project=/tmp/a/../b&title=x")!))
        #expect(link.project.path(percentEncoded: false).trimmingCharacters(in: ["/"]) == "tmp/b")
    }

    @Test func twentyLinksMakeTwentyBozzeAndNoSessione() throws {
        let store = try makeStore()

        for number in 1...20 {
            let added = store.receive(try #require(DraftLink(linkURL(number.isMultiple(of: 2)
                ? "source=github&id=\(number)" : "title=Bozza%20\(number)"))))
            #expect(added)
        }

        #expect(store.drafts.drafts.count == 20)
        #expect(store.sessions.isEmpty)
    }

    @Test func theSameLinkTwiceIsOneBozza() throws {
        let store = try makeStore()
        let link = try #require(DraftLink(linkURL("source=github&id=42&title=Login%20rotto")))

        #expect(store.receive(link))
        #expect(!store.receive(link))

        #expect(store.drafts.drafts.count == 1)
        #expect(store.drafts.drafts.first?.issue?.label == "#42")
    }

    @Test func anIssueSavedFromCommandIAndThenLinkedIsOneBozza() throws {
        let store = try makeStore()

        #expect(store.addDraft(Draft(title: "Login rotto", text: "", project: project, issue: .github(42))))
        #expect(!store.receive(try #require(DraftLink(linkURL("source=github&id=42")))))

        let draft = try #require(store.drafts.drafts.first)
        #expect(store.drafts.drafts.count == 1)
        #expect(IssueLink.github(42).match(in: store.sessions, drafts: store.drafts.drafts, on: project) == .draft(draft))
    }

    @Test func anIssueWithAnOpenSessioneGetsNoBozza() throws {
        var open = Session(id: UUID(), title: "Login rotto", project: project)
        open.issue = .github(42)
        let store = try makeStore(sessions: [open])

        #expect(!store.receive(try #require(DraftLink(linkURL("source=github&id=42")))))
        #expect(store.drafts.drafts.isEmpty)
    }

    @Test func anIssueWithAnArchivedSessioneGetsABozza() throws {
        var archived = Session(id: UUID(), title: "Login rotto", project: project)
        archived.issue = .github(42)
        archived.phase = .archiviata
        let store = try makeStore(sessions: [archived])

        #expect(store.receive(try #require(DraftLink(linkURL("source=github&id=42")))))
        #expect(store.drafts.drafts.count == 1)
    }

    @Test func theSameIssueOnAnotherProgettoIsAnotherBozza() throws {
        let other = folder.appending(path: "altro", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let store = try makeStore()

        #expect(store.receive(try #require(DraftLink(linkURL("source=github&id=42")))))
        #expect(store.receive(try #require(DraftLink(URL(string: "bubo://draft?project=\(other.path)&source=github&id=42")!))))
        #expect(store.drafts.drafts.count == 2)
    }

    @Test func aFolderThatDoesNotExistGetsNoBozza() throws {
        let store = try makeStore()
        let missing = try #require(DraftLink(URL(string: "bubo://draft?project=/tmp/bubo-sparito-\(UUID().uuidString)&title=x")!))
        let file = try #require(DraftLink(URL(string: "bubo://draft?project=\(folder.appending(path: "Sessioni.json").path)&title=x")!))

        #expect(!store.receive(missing))
        #expect(!store.receive(file))
        #expect(store.drafts.drafts.isEmpty)
    }

    @Test func aBozzaKeepsItsIssueAndOneSavedBeforeHasNone() throws {
        let draft = Draft(title: "Login rotto", text: "", project: project, issue: .github(42))
        #expect(try JSONDecoder().decode(Draft.self, from: JSONEncoder().encode(draft)) == draft)

        let old = #"{"id":"\#(UUID().uuidString)","title":"A mano","text":"","project":"file:///tmp/","createdAt":0}"#
        #expect(try JSONDecoder().decode(Draft.self, from: Data(old.utf8)).issue == nil)
    }

    @Test func theBoardFiltersBySource() {
        #expect(BoardSource.allCases == [.manual, .issue(.github)])
        #expect(BoardSource.manual.contains(nil))
        #expect(!BoardSource.manual.contains(.github(42)))
        #expect(BoardSource.issue(.github).contains(.github(42)))
        #expect(!BoardSource.issue(.github).contains(nil))
    }
}
