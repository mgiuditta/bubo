import Foundation
import Testing
@testable import Bubo

/// The visore: the `path:line[:column]` ⌘-clicked in the terminal, and the file read and highlighted (spec 15).
struct CodeViewerTests {
    let worktree = URL(filePath: "/tmp/progetto")

    @Test func aRelativePathWithLineAndColumnIsResolvedAgainstTheWorktree() throws {
        let location = try #require(SourceLocation(link: "src/main.swift:12:4", relativeTo: worktree))
        #expect(location.file.path == "/tmp/progetto/src/main.swift")
        #expect(location.line == 12)
        #expect(location.column == 4)
    }

    @Test func aDotSlashPathWithOnlyTheLine() throws {
        let location = try #require(SourceLocation(link: "./a.swift:3", relativeTo: worktree))
        #expect(location.file.path == "/tmp/progetto/a.swift")
        #expect(location.line == 3)
        #expect(location.column == nil)
    }

    @Test func aParentPathIsStandardized() throws {
        let location = try #require(SourceLocation(link: "../altro/b.ts:8", relativeTo: worktree))
        #expect(location.file.path == "/tmp/altro/b.ts")
    }

    @Test func anAbsolutePathStaysAsItIs() throws {
        let location = try #require(SourceLocation(link: "/usr/include/stdio.h:100:2", relativeTo: worktree))
        #expect(location.file.path == "/usr/include/stdio.h")
        #expect(location.line == 100)
        #expect(location.column == 2)
    }

    @Test func aHomePathIsExpanded() throws {
        let location = try #require(SourceLocation(link: "~/notes/x.md:1", relativeTo: worktree))
        #expect(location.file.path == NSString(string: "~/notes/x.md").expandingTildeInPath)
    }

    @Test func aPathWithoutLineOpensAtTheFirst() throws {
        let location = try #require(SourceLocation(link: "src/main.swift", relativeTo: worktree))
        #expect(location.file.path == "/tmp/progetto/src/main.swift")
        #expect(location.line == 1)
    }

    @Test(arguments: ["http://localhost:3000", "https://example.com/a/b.swift:3", "mailto:a@b.it", "file:///tmp/a"])
    func aURLIsNotAFile(link: String) {
        #expect(SourceLocation(link: link, relativeTo: worktree) == nil)
    }

    @Test func onlyAnExistingRegularFileOpensInTheVisore() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "CodeViewerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "src"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("x\n".utf8).write(to: folder.appending(path: "src/a.swift"))
        #expect(SourceLocation(link: "src/a.swift:1", relativeTo: folder)?.isExistingFile == true)
        #expect(SourceLocation(link: "src/b.swift:1", relativeTo: folder)?.isExistingFile == false)
        #expect(SourceLocation(link: "src/", relativeTo: folder)?.isExistingFile == false)
    }

    /// The highlighted stretches of `code` as kind and text.
    private func spans(_ code: String, fileExtension: String = "swift") -> [[(SyntaxHighlighter.Kind, String)]] {
        let lines = code.components(separatedBy: "\n")
        return zip(lines, SyntaxHighlighter.spans(of: lines, fileExtension: fileExtension)).map { line, spans in
            spans.map { ($0.kind, String(line[$0.range])) }
        }
    }

    @Test func keywordsStringsNumbersAndCommentsAreFound() {
        let found = spans(#"let name = "a // b" + 42 // fine"#)[0]
        #expect(found.map(\.0) == [.keyword, .string, .number, .comment])
        #expect(found.map(\.1) == ["let", #""a // b""#, "42", "// fine"])
    }

    @Test func aBlockCommentSpansLines() {
        let found = spans("/* uno\ndue\ntre */ return")
        #expect(found[0].map(\.1) == ["/* uno"])
        #expect(found[1].map(\.1) == ["due"])
        #expect(found[2].map(\.0) == [.comment, .keyword])
    }

    @Test func aHashCommentInPythonButNotInSwift() {
        #expect(spans("x = 1 # nota", fileExtension: "py")[0].last?.0 == .comment)
        #expect(spans("#if DEBUG", fileExtension: "swift")[0].contains { $0.0 == .comment } == false)
    }

    @Test func anEscapedQuoteStaysInsideTheString() {
        let found = spans(#"print("a\"b") // c"#)[0]
        #expect(found.map(\.1) == [#""a\"b""#, "// c"])
    }

    @Test func identifiersWithDigitsAreNotNumbers() {
        #expect(spans("var x1 = y2")[0].map(\.1) == ["var"])
    }

    @Test func markdownIsNotHighlighted() {
        #expect(spans("let's go # title", fileExtension: "md")[0].isEmpty)
    }

    @Test func linesKeepTheirTextWithoutTheFinalNewlineOrCarriageReturns() {
        let lines = CodeViewerStore.lines(of: "uno\r\ndue\n\ntre\n", fileExtension: "txt")
        #expect(lines.map(\.text) == ["uno", "due", "", "tre"])
    }

    @Test func aBinaryFileIsNotShown() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "CodeViewerTests-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data([0x41, 0x00, 0x42]).write(to: file)
        guard case .unreadable = await CodeViewerStore.read(file) else {
            Issue.record("A binary file shows in the visore")
            return
        }
    }

    @Test func aTextFileIsReadLineByLine() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "CodeViewerTests-\(UUID().uuidString).swift")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("let a = 1\nlet b = 2\n".utf8).write(to: file)
        let content = await CodeViewerStore.read(file)
        guard case let .lines(lines) = content else {
            Issue.record("The file does not show: \(content)")
            return
        }
        #expect(lines.map(\.text) == ["let a = 1", "let b = 2"])
    }
}
