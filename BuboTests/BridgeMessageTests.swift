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

    @Test func askWithAServerOffersTheAnteprima() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"),
                                         settingSources: [], offersPreview: true).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","preview":true,"prompt":"Ciao","settingSources":[],"type":"ask","v":3}"# + "\n")
    }

    @Test func offerPreviewNamesTheConversation() throws {
        let line = try BridgeCommand.offerPreview(id: "a1", isOffered: false).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"available":false,"id":"a1","type":"previewServer","v":3}"# + "\n")
    }

    @Test func answerPreviewCarriesTextImageOrFailure() throws {
        let text = try BridgeCommand.answerPreview(call: "c1", .text("ok")).line()
        #expect(String(decoding: text, as: UTF8.self) == #"{"call":"c1","text":"ok","type":"previewResult","v":3}"# + "\n")
        let image = try BridgeCommand.answerPreview(call: "c1", .image(Data([0xFF, 0xD8]))).line()
        #expect(String(decoding: image, as: UTF8.self) == #"{"call":"c1","image":"/9g=","type":"previewResult","v":3}"# + "\n")
        let failure = try BridgeCommand.answerPreview(call: "c1", .failure("no")).line()
        #expect(String(decoding: failure, as: UTF8.self) == #"{"call":"c1","error":"no","type":"previewResult","v":3}"# + "\n")
    }

    @Test(arguments: [
        (#""tool":"screenshot""#, PreviewAction.screenshot),
        (#""tool":"dom","selector":"main""#, .dom(selector: "main")),
        (#""tool":"console""#, .console(filter: nil)),
        (#""tool":"rete","filter":"api""#, .network(filter: "api")),
        (#""tool":"naviga","url":"/login""#, .navigate(to: "/login")),
        (##""tool":"clicca","selector":"#invia""##, .click(selector: "#invia")),
        (##""tool":"compila","selector":"#email","text":"a@b.it""##, .fill(selector: "#email", text: "a@b.it")),
        (#""tool":"scorri","y":-200"#, .scroll(selector: nil, offset: -200)),
        (#""tool":"esegui_js","code":"return 1""#, .runJavaScript(code: "return 1")),
    ])
    func previewCallsDecodeToTheirAction(fields: String, action: PreviewAction) throws {
        let line = #"{"v":3,"type":"previewCall","id":"a1","call":"c1","# + fields + "}"
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8))
            == .previewCall(id: "a1", call: "c1", action))
    }

    @Test func aPreviewCallBuboDoesNotKnowHasNoAction() throws {
        let line = #"{"v":3,"type":"previewCall","id":"a1","call":"c1","tool":"cancella"}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == .previewCall(id: "a1", call: "c1", nil))
        let missing = #"{"v":3,"type":"previewCall","id":"a1","call":"c1","tool":"clicca"}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(missing.utf8)) == .previewCall(id: "a1", call: "c1", nil))
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

    @Test func warmCarriesTheSourcesAndCoolNothing() throws {
        let warm = try BridgeCommand.warmConfiguration(settingSources: ["user", "project", "local"],
                                                       projectConfigRoot: URL(filePath: "/tmp/repo/")).line()
        #expect(String(decoding: warm, as: UTF8.self)
            == #"{"projectConfigRoot":"/tmp/repo","settingSources":["user","project","local"],"type":"warm","v":3}"# + "\n")
        #expect(String(decoding: try BridgeCommand.coolConfiguration.line(), as: UTF8.self) == #"{"type":"cool","v":3}"# + "\n")
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

    @Test func askKeepingAConversationCarriesItsId() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [],
                                         keeping: "k-1").line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","keep":"k-1","prompt":"Ciao","settingSources":[],"type":"ask","v":3}"# + "\n")
    }

    @Test func onlyAnAskThatRemembersCarriesRemember() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [],
                                         remembers: true).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","prompt":"Ciao","remember":true,"settingSources":[],"type":"ask","v":3}"# + "\n")
        let plain = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [])
            .line()
        #expect(!String(decoding: plain, as: UTF8.self).contains("remember"))
    }

    @Test func theCopiesAreKeptAndForgottenByCommand() throws {
        #expect(String(decoding: try BridgeCommand.keepHistory(id: "k1").line(), as: UTF8.self)
            == #"{"id":"k1","type":"keep","v":3}"# + "\n")
        #expect(String(decoding: try BridgeCommand.forget(conversations: ["c-1", "c-2"]).line(), as: UTF8.self)
            == #"{"conversations":["c-1","c-2"],"type":"forget","v":3}"# + "\n")
        #expect(String(decoding: try BridgeCommand.forgetHistory(id: "f1").line(), as: UTF8.self)
            == #"{"id":"f1","type":"forgetHistory","v":3}"# + "\n")
    }

    @Test func theCopyEventsDecode() throws {
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(#"{"v":3,"type":"kept","id":"k1","count":4}"#.utf8))
            == .kept(id: "k1", count: 4))
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(#"{"v":3,"type":"forgot","id":"f1"}"#.utf8))
            == .forgot(id: "f1"))
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
            {"v":3,"type":"config","id":"c1","skills":["prova"],"plugins":[{"name":"figma","version":"1.2.0","path":"/p/figma"},{"name":"locale"}],
             "pluginErrors":[{"plugin":"rotto@mercato","message":"manca base"}],
             "mcpServers":[{"name":"db","status":"failed","source":"project","error":"Connection closed"},{"name":"linear","status":"needs-auth"}],
             "instructions":[{"path":"/r/CLAUDE.md","type":"Project"}],
             "agents":[{"name":"Explore","description":"Cerca","model":"haiku"},{"name":"revisore","description":"Rivede"}]}
            """#
        let expected = ClaudeConfiguration(
            skills: ["prova"],
            plugins: [.init(name: "figma", version: "1.2.0", path: "/p/figma"), .init(name: "locale", version: nil)],
            pluginErrors: [.init(plugin: "rotto@mercato", message: "manca base")],
            mcpServers: [.init(name: "db", status: "failed", source: "project", error: "Connection closed"),
                         .init(name: "linear", status: "needs-auth", source: nil, error: nil)],
            instructions: [.init(path: "/r/CLAUDE.md", type: "Project")],
            agents: [.init(name: "Explore", description: "Cerca", model: "haiku"),
                     .init(name: "revisore", description: "Rivede", model: nil)])
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == .configuration(id: "c1", expected))
    }

    @Test(arguments: [
        (#"{"v":3,"type":"ready"}"#, BridgeEvent.ready),
        (#"{"v":3,"type":"text","id":"a1","text":"ci"}"#, .text(id: "a1", text: "ci")),
        (#"{"v":3,"type":"done","id":"a1"}"#, .done(id: "a1")),
        (#"{"v":3,"type":"state","id":"a1","state":"requires_action"}"#, .progress(id: "a1", .state(.requiresAction))),
        (#"{"v":3,"type":"summary","id":"a1","text":"Leggo i file"}"#, .progress(id: "a1", .summary("Leggo i file"))),
        (#"{"v":3,"type":"edit","id":"a1","file":"/w/a.swift","lines":["g()"]}"#,
         .progress(id: "a1", .edit(file: "/w/a.swift", lines: ["g()"]))),
        (#"{"v":3,"type":"ran","id":"a1"}"#, .progress(id: "a1", .ranCommand)),
        (#"{"v":3,"type":"error","id":"a1","message":"no"}"#, .error(id: "a1", message: "no")),
        (#"{"v":3,"type":"error","message":"no"}"#, .error(id: nil, message: "no")),
        (#"{"v":3,"type":"search","id":"s1","query":"ci","project":"/p"}"#, .search(id: "s1", query: "ci", project: "/p")),
        (#"{"v":3,"type":"search","id":"s1","query":"ci"}"#, .search(id: "s1", query: "ci", project: nil)),
        (#"{"v":3,"type":"search","id":"s1","query":"ci","source":"secondo-cervello"}"#,
         .search(id: "s1", query: "ci", project: nil, source: .secondBrain)),
        (#"{"v":3,"type":"search","id":"s1","query":"ci","source":"altrove"}"#, .search(id: "s1", query: "ci", project: nil)),
        (#"{"v":3,"type":"remember","id":"r1","title":"Ombrello","text":"portarlo"}"#,
         .remember(id: "r1", title: "Ombrello", text: "portarlo")),
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
