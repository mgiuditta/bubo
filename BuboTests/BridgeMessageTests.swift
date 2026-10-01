import Foundation
import Testing
@testable import Bubo

struct BridgeMessageTests {
    @Test func askCarriesTheVersionAndEndsTheLine() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"),
                                         settingSources: ["user"]).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","prompt":"Ciao","settingSources":["user"],"type":"ask","v":3}"# + "\n")
    }

    @Test func cancelNamesTheConversation() throws {
        let line = try BridgeCommand.cancel(id: "a1").line()
        #expect(String(decoding: line, as: UTF8.self) == #"{"id":"a1","type":"cancel","v":3}"# + "\n")
    }

    @Test func foundCarriesTheSearchResult() throws {
        let line = try BridgeCommand.found(id: "s1", text: "/a.md").line()
        #expect(String(decoding: line, as: UTF8.self) == #"{"id":"s1","text":"/a.md","type":"found","v":3}"# + "\n")
    }

    @Test func readQuotaAsksWithoutAConversation() throws {
        let line = try BridgeCommand.readQuota.line()
        #expect(String(decoding: line, as: UTF8.self) == #"{"type":"quota","v":3}"# + "\n")
    }

    @Test(arguments: [
        (#"{"v":3,"type":"ready"}"#, BridgeEvent.ready),
        (#"{"v":3,"type":"text","id":"a1","text":"ci"}"#, .text(id: "a1", text: "ci")),
        (#"{"v":3,"type":"done","id":"a1"}"#, .done(id: "a1")),
        (#"{"v":3,"type":"error","id":"a1","message":"no"}"#, .error(id: "a1", message: "no")),
        (#"{"v":3,"type":"error","message":"no"}"#, .error(id: nil, message: "no")),
        (#"{"v":3,"type":"search","id":"s1","query":"ci","project":"/p"}"#, .search(id: "s1", query: "ci", project: "/p")),
        (#"{"v":3,"type":"search","id":"s1","query":"ci"}"#, .search(id: "s1", query: "ci", project: nil)),
        (#"{"v":3,"type":"quota","fiveHour":{"used":0.19,"resetsAt":1790852400.5},"sevenDay":{"used":0.02,"resetsAt":1791428400}}"#,
         .quota(Quota(fiveHour: Quota.Window(used: 0.19, resetsAt: Date(timeIntervalSince1970: 1_790_852_400.5)),
                      sevenDay: Quota.Window(used: 0.02, resetsAt: Date(timeIntervalSince1970: 1_791_428_400))))),
        (#"{"v":3,"type":"quota","sevenDay":{"used":0.8,"resetsAt":1791428400}}"#,
         .quota(Quota(sevenDay: Quota.Window(used: 0.8, resetsAt: Date(timeIntervalSince1970: 1_791_428_400))))),
        (#"{"v":4,"type":"whatever"}"#, .unsupportedVersion(4)),
    ])
    func eventsDecode(line: String, event: BridgeEvent) throws {
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == event)
    }

    @Test func anUnknownEventDoesNotDecode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BridgeEvent.self, from: Data(#"{"v":3,"type":"boh"}"#.utf8))
        }
    }
}
