import Foundation
import Testing
@testable import Bubo

struct ProjectMemoryTests {
    /// A folder of its own under the temporary directory, standing for the user's home.
    let base: URL

    init() throws {
        base = URL(filePath: TrustGate.realPath(FileManager.default.temporaryDirectory.path))
            .appending(path: "ProjectMemoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func folder(_ path: String) throws -> URL {
        let url = base.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ text: String, to name: String, in directory: URL) throws {
        try Data(text.utf8).write(to: directory.appending(path: name))
    }

    // MARK: Folder

    @Test func folderNameReplacesEveryCharacterThatIsNotAnASCIILetterOrDigit() {
        #expect(ProjectMemory.folderName(ofRoot: "/Users/matteo/dev/bubo") == "-Users-matteo-dev-bubo")
        // A character outside the BMP is two UTF-16 units in the CLI's JavaScript, so two dashes.
        #expect(ProjectMemory.folderName(ofRoot: "/Users/u/Café 🦉/bubo") == "-Users-u-Caf-----bubo")
    }

    @Test func folderNamePast200CharactersEndsWithTheCLIHash() {
        let root = "/Users/u/" + String(repeating: "cartella-molto-lunga/", count: 12) + "progetto"
        let expected = "-Users-u-" + String(repeating: "cartella-molto-lunga-", count: 9) + "ca-mmmb9w"
        #expect(ProjectMemory.folderName(ofRoot: root) == expected)
    }

    @Test func everyWorktreeOfARepoSharesTheMemoryOfItsMainCheckout() throws {
        let main = try folder("repo")
        try FileManager.default.createDirectory(at: main.appending(path: ".git/worktrees/w"),
                                                withIntermediateDirectories: true)
        try write("../..\n", to: "commondir", in: main.appending(path: ".git/worktrees/w"))
        let worktree = try folder("worktrees/w")
        try write("gitdir: \(main.path)/.git/worktrees/w\n", to: ".git", in: worktree)

        let directory = ProjectMemory.directory(ofProject: main, home: base)
        #expect(directory.path == base.path + "/.claude/projects/" + ProjectMemory.folderName(ofRoot: main.path) + "/memory")
        #expect(ProjectMemory.directory(ofProject: worktree, home: base) == directory)
        #expect(ProjectMemory.directory(ofProject: try folder("repo/Sources"), home: base) == directory)
    }

    // MARK: Reading

    @Test func frontmatterGivesKindDateTitleAndSummary() throws {
        let topic = ProjectMemory.topic(named: "feedback_testing.md", text: """
            ---
            name: Test veri
            description: "Niente mock del database"
            type: feedback
            modified: 2026-09-30T12:34:56.789Z
            ---

            I test usano il database vero.
            """)
        #expect(topic.title == "Test veri")
        #expect(topic.summary == "Niente mock del database")
        #expect(topic.kind == "feedback")
        let modified = try #require(topic.modified)
        #expect(abs(modified.timeIntervalSince1970 - 1_790_771_696.789) < 0.001)
    }

    @Test func aFileWithoutFrontmatterTakesItsDateFromTheDisk() {
        let changed = Date(timeIntervalSince1970: 1_000)
        let topic = ProjectMemory.topic(named: "nota.md", text: "Solo testo", changedOnDisk: changed)
        #expect(topic.kind == nil)
        #expect(topic.title == nil)
        #expect(topic.modified == changed)
    }

    @Test func readListsTheMemoriesMostRecentFirstWithoutTheIndex() throws {
        let directory = try folder("memory")
        try write("- [A](a.md)\n- [B](b.md)", to: "MEMORY.md", in: directory)
        try write("---\ntype: user\nmodified: 2026-01-01T00:00:00Z\n---\nA", to: "a.md", in: directory)
        try write("---\ntype: project\nmodified: 2026-02-01T00:00:00Z\n---\nB", to: "b.md", in: directory)
        try write("non è un ricordo", to: "note.txt", in: directory)

        let memory = ProjectMemory.read(in: directory)
        #expect(memory.topics.map(\.name) == ["b.md", "a.md"])
        #expect(memory.index?.lineCount == 2)
    }

    @Test func aFolderThatDoesNotExistIsAnEmptyMemory() {
        let memory = ProjectMemory.read(in: base.appending(path: "assente"))
        #expect(memory.isEmpty)
    }

    // MARK: Index

    @Test(arguments: [(159, false), (160, true), (200, true)])
    func theIndexWarnsFrom80PercentOfItsLines(lines: Int, isNearLimit: Bool) {
        let index = ProjectMemory.Index(text: Array(repeating: "- [x](x.md)", count: lines).joined(separator: "\n"))
        #expect(index.lineCount == lines)
        #expect(index.isNearLimit == isNearLimit)
    }

    @Test func theIndexWarnsFrom80PercentOfItsBytes() {
        let index = ProjectMemory.Index(text: String(repeating: "x", count: 20_000))
        #expect(index.lineCount == 1)
        #expect(index.fill == 0.8)
        #expect(index.isNearLimit)
    }

    // MARK: Changing

    @Test func savingAFileThatChangedOnDiskWritesNothing() throws {
        let directory = try folder("memory")
        try write("nuovo dall'agente", to: "a.md", in: directory)

        #expect(throws: ProjectMemoryError.changedOnDisk) {
            try ProjectMemory.write("mio", to: "a.md", in: directory, expecting: "letto prima")
        }
        #expect(try String(contentsOf: directory.appending(path: "a.md"), encoding: .utf8) == "nuovo dall'agente")
    }

    @Test func savingReplacesTheFile() throws {
        let directory = try folder("memory")
        try write("prima", to: "a.md", in: directory)
        try ProjectMemory.write("dopo", to: "a.md", in: directory, expecting: "prima")
        #expect(try String(contentsOf: directory.appending(path: "a.md"), encoding: .utf8) == "dopo")
    }

    @Test func deletingAMemoryRemovesItsFileAndItsLinesInTheIndex() throws {
        let directory = try folder("memory")
        try write("# Memoria\n- [A](a.md) — uno\n- [B](b.md) — due", to: "MEMORY.md", in: directory)
        try write("A", to: "a.md", in: directory)
        try write("B", to: "b.md", in: directory)
        let memory = ProjectMemory.read(in: directory)
        let topic = try #require(memory.topics.first { $0.name == "a.md" })

        #expect(memory.index(removing: "a.md") == "# Memoria\n- [B](b.md) — due")
        try memory.delete(topic)

        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "a.md").path))
        #expect(try String(contentsOf: directory.appending(path: "MEMORY.md"), encoding: .utf8)
            == "# Memoria\n- [B](b.md) — due")
    }

    @Test func deletingWhileTheIndexChangedOnDiskTouchesNothing() throws {
        let directory = try folder("memory")
        try write("- [A](a.md)", to: "MEMORY.md", in: directory)
        try write("A", to: "a.md", in: directory)
        let memory = ProjectMemory.read(in: directory)
        try write("- [A](a.md)\n- [C](c.md)", to: "MEMORY.md", in: directory)

        #expect(throws: ProjectMemoryError.changedOnDisk) {
            try memory.delete(try #require(memory.topics.first))
        }
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "a.md").path))
    }
}
