import Foundation
import Testing
@testable import Bubo

struct SlashCompletionTests {
    /// Skills read from command files named `names`, in a temporary folder.
    private func skills(_ names: [String]) throws -> [Skill] {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try names.map { name in
            let file = folder.appending(path: "\(name).md")
            try "Do \(name).".write(to: file, atomically: true, encoding: .utf8)
            return try #require(Skill(file: file, name: name, directory: nil, source: .user))
        }
    }

    @Test(arguments: [("/", ""), ("/rev", "rev"), ("/caveman:review", "caveman:review")])
    func queryFollowsTheSlashAtTheStart(text: String, query: String) {
        #expect(SlashCompletion.query(in: text) == query)
    }

    @Test(arguments: ["", "review", "a /review", " /review", "/review the diff", "/review\n"])
    func noQueryElsewhereOrAfterASpace(text: String) {
        #expect(SlashCompletion.query(in: text) == nil)
    }

    @Test func matchesStartWithThePrefixThenContainIt() throws {
        let catalog = try skills(["code-review", "Review", "rewrite", "simplify"])
        #expect(SlashCompletion.matches(for: "rev", in: catalog).map(\.name) == ["Review", "code-review"])
    }

    @Test func emptyQueryShowsAtMostEight() throws {
        let catalog = try skills((1...10).map { "skill\($0)" })
        #expect(SlashCompletion.matches(for: "", in: catalog).count == SlashCompletion.limit)
        #expect(SlashCompletion.matches(for: "zzz", in: catalog).isEmpty)
    }

    @Test func completionLeavesASpaceForTheRequest() throws {
        let skill = try #require(try skills(["review"]).first)
        let completed = SlashCompletion.completion(for: skill)
        #expect(completed == "/review ")
        #expect(SlashCompletion.query(in: completed) == nil)
    }
}
