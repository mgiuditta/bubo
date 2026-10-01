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

    @Test func askInAWorktreeCarriesTheMainCheckout() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/w"),
                                         settingSources: ["user"], projectConfigRoot: URL(filePath: "/tmp/repo/")).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/w","id":"a1","projectConfigRoot":"/tmp/repo","prompt":"Ciao","settingSources":["user"],"type":"ask","v":3}"# + "\n")
    }

    @Test func askWithAModelCarriesIt() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"),
                                         settingSources: [], model: "sonnet").line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","model":"sonnet","prompt":"Ciao","settingSources":[],"type":"ask","v":3}"# + "\n")
    }

    @Test func askWithAnEnvironmentCarriesIt() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"),
                                         settingSources: [], environment: ["PORT": "40000"]).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","env":{"PORT":"40000"},"id":"a1","prompt":"Ciao","settingSources":[],"type":"ask","v":3}"# + "\n")
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

    @Test func inspectCarriesTheFolderAndItsSources() throws {
        let line = try BridgeCommand.inspect(id: "c1", directory: URL(filePath: "/tmp/w"), settingSources: ["user"],
                                             projectConfigRoot: URL(filePath: "/tmp/repo/")).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/w","id":"c1","projectConfigRoot":"/tmp/repo","settingSources":["user"],"type":"config","v":3}"# + "\n")
    }

    @Test func askResumingAConversationCarriesIt() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [],
                                         resuming: "c-1").line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","prompt":"Ciao","resume":"c-1","settingSources":[],"type":"ask","v":3}"# + "\n")
    }

    @Test func readHistoryAsksForTheFirstPageOrAll() throws {
        #expect(String(decoding: try BridgeCommand.readHistory(id: "h1", isComplete: false).line(), as: UTF8.self)
            == #"{"all":false,"id":"h1","type":"history","v":3}"# + "\n")
        #expect(String(decoding: try BridgeCommand.readTranscript(id: "t1", conversation: "c-1").line(), as: UTF8.self)
            == #"{"conversation":"c-1","id":"t1","type":"transcript","v":3}"# + "\n")
    }

    @Test func theHistoryAndATranscriptDecode() throws {
        let history = #"""
            {"v":3,"type":"history","id":"h1","conversations":[
             {"id":"c-1","title":"Correggi il login","cwd":"/r/app","branch":"main","lastModified":1790846145117},
             {"id":"c-2","title":"Senza cartella","lastModified":0}]}
            """#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(history.utf8)) == .history(id: "h1", [
            CLIConversation(id: "c-1", title: "Correggi il login", folder: URL(filePath: "/r/app", directoryHint: .isDirectory),
                            branch: "main", lastModified: Date(timeIntervalSince1970: 1_790_846_145.117)),
            CLIConversation(id: "c-2", title: "Senza cartella", folder: nil, branch: nil,
                            lastModified: Date(timeIntervalSince1970: 0)),
        ]))
        let transcript = #"""
            {"v":3,"type":"transcript","id":"t1","messages":[{"role":"user","text":"Ciao"},{"role":"assistant","text":"Eccomi"}]}
            """#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(transcript.utf8)) == .transcript(id: "t1", [
            CLIConversation.Message(isFromUser: true, text: "Ciao"), CLIConversation.Message(isFromUser: false, text: "Eccomi"),
        ]))
    }

    @Test func theConfigurationDecodes() throws {
        let line = #"""
            {"v":3,"type":"config","id":"c1","skills":["prova"],"plugins":[{"name":"figma","version":"1.2.0"},{"name":"locale"}],
             "pluginErrors":[{"plugin":"rotto@mercato","message":"manca base"}],
             "mcpServers":[{"name":"db","status":"failed","source":"project","error":"Connection closed"},{"name":"linear","status":"needs-auth"}],
             "instructions":[{"path":"/r/CLAUDE.md","type":"Project"}]}
            """#
        let expected = ClaudeConfiguration(
            skills: ["prova"],
            plugins: [.init(name: "figma", version: "1.2.0"), .init(name: "locale", version: nil)],
            pluginErrors: [.init(plugin: "rotto@mercato", message: "manca base")],
            mcpServers: [.init(name: "db", status: "failed", source: "project", error: "Connection closed"),
                         .init(name: "linear", status: "needs-auth", source: nil, error: nil)],
            instructions: [.init(path: "/r/CLAUDE.md", type: "Project")])
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == .configuration(id: "c1", expected))
    }

    @Test(arguments: [
        (#"{"v":3,"type":"ready"}"#, BridgeEvent.ready),
        (#"{"v":3,"type":"text","id":"a1","text":"ci"}"#, .text(id: "a1", text: "ci")),
        (#"{"v":3,"type":"done","id":"a1"}"#, .done(id: "a1")),
        (#"{"v":3,"type":"state","id":"a1","state":"requires_action"}"#, .progress(id: "a1", .state(.requiresAction))),
        (#"{"v":3,"type":"summary","id":"a1","text":"Leggo i file"}"#, .progress(id: "a1", .summary("Leggo i file"))),
        (#"{"v":3,"type":"error","id":"a1","message":"no"}"#, .error(id: "a1", message: "no")),
        (#"{"v":3,"type":"error","message":"no"}"#, .error(id: nil, message: "no")),
        (#"{"v":3,"type":"search","id":"s1","query":"ci","project":"/p"}"#, .search(id: "s1", query: "ci", project: "/p")),
        (#"{"v":3,"type":"search","id":"s1","query":"ci"}"#, .search(id: "s1", query: "ci", project: nil)),
        (#"{"v":3,"type":"quota","fiveHour":{"used":0.19,"resetsAt":1790852400.5},"sevenDay":{"used":0.02,"resetsAt":1791428400}}"#,
         .quota(Quota(fiveHour: Quota.Window(used: 0.19, resetsAt: Date(timeIntervalSince1970: 1_790_852_400.5)),
                      sevenDay: Quota.Window(used: 0.02, resetsAt: Date(timeIntervalSince1970: 1_791_428_400))))),
        (#"{"v":3,"type":"quota","sevenDay":{"used":0.8,"resetsAt":1791428400}}"#,
         .quota(Quota(sevenDay: Quota.Window(used: 0.8, resetsAt: Date(timeIntervalSince1970: 1_791_428_400))))),
        (#"{"v":3,"type":"limit","id":"a1","window":"five_hour","resetsAt":1790852400}"#,
         .limit(id: "a1", reached: Quota.Limit(window: "five_hour", resetsAt: Date(timeIntervalSince1970: 1_790_852_400)))),
        (#"{"v":3,"type":"limit","id":"a1"}"#, .limit(id: "a1", reached: Quota.Limit())),
        (#"{"v":3,"type":"signInRequired","id":"a1"}"#, .signInRequired(id: "a1")),
        (#"{"v":3,"type":"permissionWithdrawn","id":"a1","request":"p1"}"#, .permissionWithdrawn(id: "a1", request: "p1")),
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

    @Test func anAnswerToAPermissionIsAllowOrDeny() throws {
        #expect(String(decoding: try BridgeCommand.answerPermission(request: "p1", allows: true).line(), as: UTF8.self)
            == #"{"behavior":"allow","request":"p1","type":"permission","v":3}"# + "\n")
        #expect(String(decoding: try BridgeCommand.answerPermission(request: "p1", allows: false).line(), as: UTF8.self)
            == #"{"behavior":"deny","request":"p1","type":"permission","v":3}"# + "\n")
    }

    @Test func aPermissionRequestDecodes() throws {
        let line = #"{"v":3,"type":"permission","id":"a1","request":"p1","tool":"Bash","command":"git push -f","#
            + #""title":"Claude wants to run git push -f","description":"Push","fromSubagent":true,"suppressAlwaysAllowRule":true}"#
        var request = PermissionRequest(id: "p1", tool: "Bash", command: "git push -f")
        request.title = "Claude wants to run git push -f"
        request.detail = "Push"
        request.isFromSubagent = true
        request.suppressesRule = true
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == .permission(id: "a1", request))
    }
}
