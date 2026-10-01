import Testing
@testable import Bubo

/// The line of the file after the change for a diff line, from the blocco's `@@` header: the visore opens there
/// (spec 15).
struct DiffLineNumberTests {
    private func hunk(_ header: String, _ lines: [(Hunk.Line.Kind, String)]) -> Hunk {
        Hunk(path: "a.swift", header: header, lines: lines.map { Hunk.Line(kind: $0.0, text: $0.1) })
    }

    @Test func unchangedAndAddedLinesCountFromTheNewStart() {
        let hunk = hunk("@@ -10,3 +12,4 @@ func route() {", [
            (.context, "a"), (.added, "b"), (.context, "c"), (.context, "d"),
        ])
        #expect((0..<4).map { hunk.newFileLine(at: $0) } == [12, 13, 14, 15])
    }

    @Test func aRemovedLineIsAtTheLineThatTakesItsPlace() {
        let hunk = hunk("@@ -1,4 +1,4 @@", [
            (.context, "a"), (.removed, "b"), (.removed, "c"), (.added, "B"), (.added, "C"), (.context, "d"),
        ])
        #expect((0..<6).map { hunk.newFileLine(at: $0) } == [1, 2, 2, 2, 3, 4])
    }

    @Test func aRemovedLineWithNothingAfterItIsAtTheLineBefore() {
        let hunk = hunk("@@ -8,3 +8,1 @@", [(.context, "a"), (.removed, "b"), (.removed, "c")])
        #expect(hunk.newFileLine(at: 1) == 8)
        #expect(hunk.newFileLine(at: 2) == 8)
    }

    @Test func withoutContextAnEmptyNewRangeNamesTheLineBefore() {
        // `-U0`: the two lines went after line 4 of the new file.
        let hunk = hunk("@@ -5,2 +4,0 @@", [(.removed, "x"), (.removed, "y")])
        #expect(hunk.newFileLine(at: 0) == 4)
        #expect(hunk.newFileLine(at: 1) == 4)
    }

    @Test func aNewFileWithoutCountsStartsAtTheFirstLine() {
        let hunk = hunk("@@ -0,0 +1 @@", [(.added, "titolo")])
        #expect(hunk.newFileLine(at: 0) == 1)
    }

    @Test func anEmptiedFileStaysAtTheFirstLine() {
        let hunk = hunk("@@ -1,2 +0,0 @@", [(.removed, "a"), (.removed, "b")])
        #expect(hunk.newFileLine(at: 0) == 1)
    }

    @Test func aHeaderThatIsNotABloccoHasNoLine() {
        let hunk = hunk("Binary files a/x.png and b/x.png differ", [(.added, "?")])
        #expect(hunk.newFileLine(at: 0) == nil)
    }

    @Test func anIndexOutsideTheBloccoHasNoLine() {
        let hunk = hunk("@@ -1 +1 @@", [(.context, "a")])
        #expect(hunk.newFileLine(at: 1) == nil)
        #expect(hunk.newFileLine(atPair: 1) == nil)
    }

    @Test func sideBySideARowIsAtItsLineAfterOrWhereItsLineBeforeWent() {
        let hunk = hunk("@@ -20,6 +30,6 @@", [
            (.context, "a"), (.removed, "b"), (.removed, "c"), (.added, "B"), (.added, "C"), (.added, "D"),
            (.context, "e"), (.removed, "f"),
        ])
        // Pairs: a|a, b|B, c|C, -|D, e|e, f|-.
        #expect((0..<6).map { hunk.newFileLine(atPair: $0) } == [30, 31, 32, 33, 34, 34])
    }

    @Test func theLinesOfAParsedDiffFollowTheirHeaders() throws {
        let file = try #require(ChangedFile.files(in: ReviewTests.diff).first)
        #expect(file.hunks[0].newFileLine(at: 2) == 2)
        #expect(file.hunks[1].newFileLine(at: 1) == 11)
    }
}
