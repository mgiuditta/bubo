import Foundation
import Testing
@testable import Bubo

struct BridgeMessageTests {
    @Test func askCarriesTheVersionAndEndsTheLine() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x")).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","prompt":"Ciao","type":"ask","v":1}"# + "\n")
    }

    @Test func cancelNamesTheConversation() throws {
        let line = try BridgeCommand.cancel(id: "a1").line()
        #expect(String(decoding: line, as: UTF8.self) == #"{"id":"a1","type":"cancel","v":1}"# + "\n")
    }

    @Test(arguments: [
        (#"{"v":1,"type":"ready"}"#, BridgeEvent.ready),
        (#"{"v":1,"type":"text","id":"a1","text":"ci"}"#, .text(id: "a1", text: "ci")),
        (#"{"v":1,"type":"done","id":"a1"}"#, .done(id: "a1")),
        (#"{"v":1,"type":"error","id":"a1","message":"no"}"#, .error(id: "a1", message: "no")),
        (#"{"v":1,"type":"error","message":"no"}"#, .error(id: nil, message: "no")),
        (#"{"v":2,"type":"whatever"}"#, .unsupportedVersion(2)),
    ])
    func eventsDecode(line: String, event: BridgeEvent) throws {
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == event)
    }

    @Test func anUnknownEventDoesNotDecode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BridgeEvent.self, from: Data(#"{"v":1,"type":"boh"}"#.utf8))
        }
    }
}
