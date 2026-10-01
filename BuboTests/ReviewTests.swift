import Foundation
import Testing
@testable import Bubo

struct ReviewTests {
    static let diff = """
    diff --git a/Sources/Router.swift b/Sources/Router.swift
    index 1111111..2222222 100644
    --- a/Sources/Router.swift
    +++ b/Sources/Router.swift
    @@ -1,3 +1,3 @@ struct Router {
     let a = 1
    -let b = 2
    +let b = 3
     let c = 4
    @@ -10,2 +10,3 @@ func route() {
     return
    +// fine
    \\ No newline at end of file
    diff --git a/nuovo file.md b/nuovo file.md
    new file mode 100644
    index 0000000..3333333
    --- /dev/null
    +++ b/nuovo file.md
    @@ -0,0 +1 @@
    +--- titolo
    diff --git a/via.txt b/via.txt
    deleted file mode 100644
    index 4444444..0000000
    --- a/via.txt
    +++ /dev/null
    @@ -1 +0,0 @@
    -x
    diff --git a/vecchio.txt b/nuovo.txt
    similarity index 100%
    rename from vecchio.txt
    rename to nuovo.txt
    diff --git a/logo.png b/logo.png
    index 5555555..6666666 100644
    Binary files a/logo.png and b/logo.png differ

    """

    @Test func gitDiffBecomesFilesAndBlocchi() throws {
        let files = ChangedFile.files(in: Self.diff)

        #expect(files.map(\.path) == ["Sources/Router.swift", "nuovo file.md", "via.txt", "nuovo.txt", "logo.png"])
        #expect(files.map(\.hunks.count) == [2, 1, 1, 1, 1])
        let router = try #require(files.first)
        #expect(router.hunks.map(\.added) == [1, 1])
        #expect(router.hunks.map(\.removed) == [1, 0])
        #expect(router.hunks[1].lines.map(\.text) == ["return", "// fine"])
        #expect(files[1].hunks[0].lines == [Hunk.Line(kind: .added, text: "--- titolo")])
        #expect(files[3].oldPath == "vecchio.txt")
        #expect(files[3].hunks[0].lines.isEmpty)
        #expect(files[4].isBinary)
    }

    @Test func aBloccoKeepsItsIdWhenItMovesButNotWhenItChanges() {
        let lines = [Hunk.Line(kind: .removed, text: "b"), Hunk.Line(kind: .added, text: "B")]
        let moved = Hunk(path: "a.txt", header: "@@ -10 +10 @@", lines: lines)
        #expect(Hunk(path: "a.txt", header: "@@ -1 +1 @@", lines: lines).id == moved.id)
        #expect(Hunk(path: "a.txt", header: "@@ -1 +1 @@", lines: [lines[0]]).id != moved.id)
        #expect(Hunk(path: "b.txt", header: "@@ -1 +1 @@", lines: lines).id != moved.id)
    }

    @Test func twoIdenticalBlocchiInAFileHaveTheirOwnIds() {
        let diff = """
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -1 +1,2 @@
        +x
        @@ -9 +10,2 @@
        +x
        """
        let ids = ChangedFile.files(in: diff).flatMap(\.hunks).map(\.id)
        #expect(Set(ids).count == 2)
    }

    /// Ten files, fourteen blocchi: one key per blocco, since the cursor moves to the next undecided one, and ⌘↩.
    @Test func tenFilesAndFourteenBlocchiAreReviewedInAtMostSixteenActions() throws {
        let files = (0..<10).map { index in
            ChangedFile(path: "file\(index).swift", hunks: (0..<(index < 4 ? 2 : 1)).map { hunk in
                Hunk(path: "file\(index).swift", header: "@@ -\(hunk) @@", lines: [Hunk.Line(kind: .added, text: "\(hunk)")])
            })
        }
        let review = Review(files: files)
        #expect(review.hunkIDs.count == 14)
        var decisions: [String: HunkDecision] = [:]
        var cursor = try #require(review.hunkIDs.first)
        var actions = 0
        while review.decidedCount(in: decisions) < review.hunkIDs.count {
            decisions[cursor] = cursor == review.hunkIDs[5] ? .rejected(note: nil) : .accepted
            cursor = review.nextUndecided(after: cursor, in: decisions)
            actions += 1
        }
        #expect(review.canSendBack(with: decisions))
        actions += 1

        #expect(actions <= 16)
    }

    @Test func theCursorMovesBetweenBlocchiAndStopsAtTheEnds() {
        let review = Review(files: ChangedFile.files(in: Self.diff))
        let ids = review.hunkIDs
        #expect(review.hunk(movingBy: 1, from: nil) == ids[0])
        #expect(review.hunk(movingBy: 1, from: ids[0]) == ids[1])
        #expect(review.hunk(movingBy: -1, from: ids[0]) == ids[0])
        #expect(review.hunk(movingBy: 1, from: ids[5]) == ids[5])
        #expect(review.nextUndecided(after: ids[5], in: [ids[0]: .accepted]) == ids[1])
        #expect(review.nextUndecided(after: ids[0], in: Dictionary(uniqueKeysWithValues: ids.map { ($0, .accepted) })) == ids[0])
    }

    @Test func sideBySideEachRemovedLineIsNextToTheLineAddedInItsPlace() {
        let context = Hunk.Line(kind: .context, text: "a")
        let removed = ["b", "c"].map { Hunk.Line(kind: .removed, text: $0) }
        let added = ["B", "C", "D"].map { Hunk.Line(kind: .added, text: $0) }
        let onlyRemoved = Hunk.Line(kind: .removed, text: "e")

        let pairs = Hunk.pairs(of: [context] + removed + added + [context, onlyRemoved])

        #expect(pairs == [
            Hunk.Pair(before: context, after: context),
            Hunk.Pair(before: removed[0], after: added[0]),
            Hunk.Pair(before: removed[1], after: added[1]),
            Hunk.Pair(before: nil, after: added[2]),
            Hunk.Pair(before: context, after: context),
            Hunk.Pair(before: onlyRemoved, after: nil),
        ])
    }

    @Test func theSideBySideDiffHasAHeaderRowForEveryBlocco() throws {
        let review = Review(files: ChangedFile.files(in: Self.diff))
        for id in review.hunkIDs {
            let row = try #require(review.sideBySideRow(of: id))
            guard case let .hunk(file, hunk) = review.sideBySideRows[row].kind else {
                Issue.record("Row \(row) is not a blocco's header")
                continue
            }
            #expect(review.files[file].hunks[hunk].id == id)
        }
        #expect(review.sideBySideRows.count { if case .pair = $0.kind { true } else { false } }
                == review.files.flatMap(\.hunks).reduce(0) { $0 + $1.pairs.count })
    }

    @Test func onlyAllDecidedWithARejectedOneGoesBackToTheAgent() {
        let review = Review(files: ChangedFile.files(in: Self.diff))
        var decisions = Dictionary(uniqueKeysWithValues: review.hunkIDs.map { ($0, HunkDecision.accepted) })
        #expect(!review.canSendBack(with: decisions))
        decisions[review.hunkIDs[0]] = .rejected(note: "Lascia 2")
        #expect(review.canSendBack(with: decisions))
        decisions[review.hunkIDs[1]] = nil
        #expect(!review.canSendBack(with: decisions))
    }

    @Test func onlyEveryBloccoAcceptedCanBeMerged() {
        let review = Review(files: ChangedFile.files(in: Self.diff))
        var decisions = Dictionary(uniqueKeysWithValues: review.hunkIDs.map { ($0, HunkDecision.accepted) })
        #expect(review.canMerge(with: decisions))
        decisions[review.hunkIDs[0]] = .rejected(note: nil)
        #expect(!review.canMerge(with: decisions))
        decisions[review.hunkIDs[0]] = nil
        #expect(!review.canMerge(with: decisions))
        #expect(!Review().canMerge(with: [:]))
    }

    @Test func theMergeMessageIsTheTitleThenEachPerchéOnce() {
        var session = Session(id: UUID(), title: "Router più chiaro", project: URL(filePath: "/p"))
        session.apply(.summary("Rinomino b"))
        session.apply(.edit(file: "/w/Sources/Router.swift", lines: ["let b = 3"]))
        session.apply(.summary("Aggiungo un commento"))
        session.apply(.edit(file: "/w/Sources/Router.swift", lines: ["// fine"]))
        let review = Review(files: ChangedFile.files(in: Self.diff))

        #expect(review.mergeMessage(for: session) == "Router più chiaro\n\n- Rinomino b\n- Aggiungo un commento")
        #expect(Review().mergeMessage(for: session) == "Router più chiaro")
    }

    @Test func theFeedbackHasTheRejectedBlocchiWithTheirNotes() {
        let review = Review(files: ChangedFile.files(in: Self.diff))
        let feedback = review.feedback(for: [review.hunkIDs[0]: .rejected(note: "Lascia 2"), review.hunkIDs[1]: .accepted])

        #expect(feedback.contains("Sources/Router.swift"))
        #expect(feedback.contains("-let b = 2\n+let b = 3"))
        #expect(feedback.contains("Lascia 2"))
        #expect(!feedback.contains("// fine"))
    }

    @Test func theReasonIsTheWriteWithTheBloccosLinesOrTheLatestOfTheFile() {
        var session = Session(id: UUID(), title: "Prova", project: URL(filePath: "/p"))
        session.apply(.edit(file: "/w/a.swift", lines: ["ignorata"]))
        #expect(session.edits.isEmpty)
        session.apply(.summary("Rinomino b"))
        session.apply(.edit(file: "/w/a.swift", lines: ["let b = 3"]))
        session.apply(.summary("Aggiungo un commento"))
        session.apply(.edit(file: "/w/a.swift", lines: ["// fine"]))
        let renamed = Hunk(path: "a.swift", header: "@@", lines: [Hunk.Line(kind: .added, text: "  let b = 3")])
        let other = Hunk(path: "a.swift", header: "@@", lines: [Hunk.Line(kind: .added, text: "altro")])

        #expect(session.reason(for: renamed, inFileAt: "a.swift") == "Rinomino b")
        #expect(session.reason(for: other, inFileAt: "a.swift") == "Aggiungo un commento")
        #expect(session.reason(for: other, inFileAt: "b.swift") == nil)
    }

    @MainActor
    @Test func sendingBackKeepsOnlyTheAcceptedBlocchiStillInTheDiff() throws {
        let folder = FileManager.default.temporaryDirectory
        var saved = Session(id: UUID(), title: "Prova", project: folder, workspace: Workspace(folder: folder, branch: "b"),
                            activity: .ferma)
        saved.decisions = ["tenuto": .accepted, "rifiutato": .rejected(note: "no"), "sparito": .accepted]
        let file = folder.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONEncoder().encode([saved]).write(to: file)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: folder)) { throw CancellationError() }

        store.sendBack("Rifai", to: saved.id, keepingAcceptedAmong: ["tenuto", "rifiutato"])

        #expect(store.sessions.first?.decisions == ["tenuto": .accepted])
        #expect(store.sessions.first?.activity == .lavora)
    }
}
