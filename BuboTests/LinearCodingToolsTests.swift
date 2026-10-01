import Foundation
import Testing
@testable import Bubo

/// Collega and Scollega Linear on a `coding-tools.json` in a temporary home: the user's keys stay, the user's script
/// comes back, a file that is not valid JSON is never written.
final class LinearCodingToolsTests {
    let home: URL
    let suite: String
    let tools: LinearCodingTools

    init() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "LinearCodingToolsTests-\(UUID().uuidString)",
                                                                directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        suite = "LinearCodingToolsTests-\(UUID().uuidString)"
        tools = LinearCodingTools(home: home,
                                  helper: URL(filePath: "/Applications/Bubo.app/Contents/Helpers/bubo-linear"),
                                  defaults: try #require(UserDefaults(suiteName: suite)))
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: home)
    }

    var file: URL { home.appending(path: ".linear/coding-tools.json") }

    func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func contents() throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }

    @Test func collegaWithNoFileWritesOnlyBubosScript() throws {
        #expect(try !tools.isConnected())

        try tools.connect()

        let script = try #require(try contents()["openIssue"] as? [String: Any])
        #expect(script["path"] as? String == "/Applications/Bubo.app/Contents/Helpers/bubo-linear")
        #expect(script["env"] as? [String] == ["LINEAR_PROMPT", "LINEAR_ISSUE_IDENTIFIER", "LINEAR_ISSUE_BRANCH_NAME",
                                              "LINEAR_WORK_DIR"])
        #expect(try contents().count == 1)
        #expect(try tools.isConnected())
        #expect(tools.scriptText.contains("\"path\" : \"/Applications/Bubo.app/Contents/Helpers/bubo-linear\""))
    }

    @Test func theOtherKeysStayAfterCollegaAndScollega() throws {
        try write(#"{"altro": {"path": "/usr/local/bin/x", "args": ["{{prompt}}"]}, "versione": 2, "attivo": true}"#)

        try tools.connect()
        #expect((try contents()["altro"] as? [String: Any])?["args"] as? [String] == ["{{prompt}}"])
        try tools.disconnect()

        let contents = try contents()
        #expect(contents["openIssue"] == nil)
        #expect((contents["altro"] as? [String: Any])?["path"] as? String == "/usr/local/bin/x")
        #expect(contents["versione"] as? Int == 2)
        #expect(contents["attivo"] as? Bool == true)
        #expect(contents.count == 3)
    }

    @Test func theUsersScriptIsShownReplacedAndPutBack() throws {
        try write(#"{"openIssue": {"path": "/Users/me/bin/mio.sh", "args": ["{{issue.identifier}}"], "env": ["LINEAR_PROMPT"]}}"#)
        #expect(try tools.otherScriptText()?.contains("/Users/me/bin/mio.sh") == true)

        try tools.connect()
        #expect(try tools.isConnected())
        #expect(try tools.otherScriptText() == nil)
        // A second Collega, from another copy of Bubo, does not lose the user's script.
        try tools.connect()
        try tools.disconnect()

        let script = try #require(try contents()["openIssue"] as? [String: Any])
        #expect(script["path"] as? String == "/Users/me/bin/mio.sh")
        #expect(script["args"] as? [String] == ["{{issue.identifier}}"])
        #expect(try !tools.isConnected())
    }

    @Test func scollegaLeavesAScriptThatIsNotBubos() throws {
        let text = #"{"openIssue": {"path": "/Users/me/bin/mio.sh"}}"#
        try write(text)

        try tools.disconnect()

        #expect(try String(contentsOf: file, encoding: .utf8) == text)
    }

    @Test(arguments: ["{ non è json", "[1, 2]", "", "\"testo\""])
    func aFileThatIsNotValidJSONIsNeverWritten(_ text: String) throws {
        try write(text)

        #expect(throws: LinearCodingTools.Failure.notValidJSON(path: file.path)) { try tools.connect() }
        #expect(throws: LinearCodingTools.Failure.notValidJSON(path: file.path)) { try tools.disconnect() }
        #expect(throws: LinearCodingTools.Failure.notValidJSON(path: file.path)) { try tools.isConnected() }
        #expect(try String(contentsOf: file, encoding: .utf8) == text)
    }

    @Test func aFileBehindALinkIsWrittenThroughIt() throws {
        let real = home.appending(path: "dotfiles/coding-tools.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"altro": 1}"#.utf8).write(to: real)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: real)

        try tools.connect()

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: file.path) == real.path)
        let contents = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: real)) as? [String: Any])
        #expect(contents["altro"] as? Int == 1)
        #expect(contents["openIssue"] != nil)
    }
}
