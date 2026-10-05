import Foundation
import Testing
@testable import Bubo

struct BridgeMessageTests {
    @Test func askCarriesTheVersionAndEndsTheLine() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"),
                                         settingSources: ["user"]).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","prompt":"Ciao","settingSources":["user"],"type":"ask","v":4}"# + "\n")
    }

    // ADR 0012: a Sessione on Copilot names the user's `copilot`, and its model and effort only when chosen.
    @Test func askCopilotCarriesTheBinaryAndTheFolder() throws {
        let line = try BridgeCommand.askCopilot(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/w"),
                                                copilot: URL(filePath: "/opt/homebrew/bin/copilot")).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"copilot":"/opt/homebrew/bin/copilot","cwd":"/tmp/w","id":"a1","prompt":"Ciao","type":"copilot","v":4}"# + "\n")
        let chosen = try BridgeCommand.askCopilot(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/w"),
                                                  copilot: URL(filePath: "/c"), model: "gpt-6", effort: .high).line()
        #expect(String(decoding: chosen, as: UTF8.self).contains(#""effort":"high","id":"a1","model":"gpt-6""#))
        let resumed = try BridgeCommand.askCopilot(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/w"),
                                                   copilot: URL(filePath: "/c"), keeping: "k-1", resumes: true).line()
        #expect(String(decoding: resumed, as: UTF8.self).contains(#""keep":"k-1","prompt":"Ciao","resume":true"#))
        let autonomous = try BridgeCommand.askCopilot(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/w"),
                                                      copilot: URL(filePath: "/c"), permissionMode: .autonomous).line()
        #expect(String(decoding: autonomous, as: UTF8.self).contains(#""permissionMode":"auto""#))
        #expect(!String(decoding: autonomous, as: UTF8.self).contains("unattended"))
        let unattended = try BridgeCommand.askCopilot(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/w"),
                                                      copilot: URL(filePath: "/c"), isUnattended: true).line()
        #expect(String(decoding: unattended, as: UTF8.self).contains(#""unattended":true"#))
    }

    @Test func askWithAllegatiCarriesTheirFolders() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"),
                                         settingSources: [], readableDirectories: [URL(filePath: "/tmp/allegati/")]).line()
        #expect(String(decoding: line, as: UTF8.self).contains(#""dirs":["/tmp/allegati"]"#))
    }

    // #678: a Domanda only reads, and never the excluded folders of the Secondo cervello.
    @Test func readOnlyAskCarriesTheSecondBrainAndItsHiddenFolders() throws {
        let readOnly = ReadOnlyTurn(isInSecondBrain: true, hiddenDirectories: [URL(filePath: "/tmp/note/Privato/")])
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/note"),
                                         settingSources: [], readOnly: readOnly).line()
        #expect(String(decoding: line, as: UTF8.self).contains(#""readOnly":{"brain":true,"hidden":["/tmp/note/Privato"]}"#))
        let ordinary = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"),
                                             settingSources: []).line()
        #expect(!String(decoding: ordinary, as: UTF8.self).contains("readOnly"))
    }

    // #165: the residue of the tightest Budget goes as the turn's cap; at the cap the turn ends apart.
    @Test func askWithABudgetCarriesItsCap() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [],
                                         maxBudget: Decimal(string: "2.5")).line()
        #expect(String(decoding: line, as: UTF8.self).contains(#""maxBudget":2.5"#))
        let event = try JSONDecoder().decode(BridgeEvent.self,
                                             from: Data(#"{"v":4,"type":"budgetExhausted","id":"a1"}"#.utf8))
        #expect(event == .budgetExhausted(id: "a1"))
    }

    @Test func askInAWorktreeCarriesTheMainCheckout() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/w"),
                                         settingSources: ["user"], projectConfigRoot: URL(filePath: "/tmp/repo/")).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/w","id":"a1","projectConfigRoot":"/tmp/repo","prompt":"Ciao","settingSources":["user"],"type":"ask","v":4}"# + "\n")
    }

    @Test func askWithAModelCarriesIt() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"),
                                         settingSources: [], model: "sonnet").line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","model":"sonnet","prompt":"Ciao","settingSources":[],"type":"ask","v":4}"# + "\n")
    }

    @Test func askWithTheRoutersEffortCarriesIt() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"),
                                         settingSources: [], model: "sonnet", effort: .low).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","effort":"low","id":"a1","model":"sonnet","prompt":"Ciao","settingSources":[],"type":"ask","v":4}"# + "\n")
    }

    @Test func answeredByCarriesTheEffectiveEffortOrNone() throws {
        let decoder = JSONDecoder()
        let opus = #"{"v":4,"type":"answeredBy","id":"a1","model":"claude-opus-5-5","effort":"high"}"#
        #expect(try decoder.decode(BridgeEvent.self, from: Data(opus.utf8))
            == .answeredBy(id: "a1", AnsweringModel(model: "claude-opus-5-5", effort: .high)))
        let haiku = #"{"v":4,"type":"answeredBy","id":"a1","model":"claude-haiku-4-5-20251001"}"#
        #expect(try decoder.decode(BridgeEvent.self, from: Data(haiku.utf8))
            == .answeredBy(id: "a1", AnsweringModel(model: "claude-haiku-4-5-20251001", effort: nil)))
    }

    @Test func modelsSkipAnEffortLevelBuboDoesNotKnow() throws {
        let line = #"{"v":4,"type":"models","models":[{"value":"haiku","resolvedModel":"claude-haiku-4-5-20251001","#
            + #""displayName":"Haiku"},{"value":"opus","displayName":"Opus","supportedEffortLevels":["low","medium","ultra"]}]}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == .models(ModelCatalog(entries: [
            ModelCatalog.Entry(value: "haiku", resolvedModel: "claude-haiku-4-5-20251001", displayName: "Haiku"),
            ModelCatalog.Entry(value: "opus", displayName: "Opus", supportedEffortLevels: [.low, .medium]),
        ])))
    }

    @Test func aCopilotQuestionCarriesItsCopilotModelAndEffort() throws {
        let line = try BridgeCommand.askCopilotQuestion(id: "c1", prompt: "Ciao", directory: URL(filePath: "/tmp/vuota"),
                                                        copilot: URL(filePath: "/opt/homebrew/bin/copilot"),
                                                        model: "gpt-6", effort: .high).line()
        #expect(String(decoding: line, as: UTF8.self) == #"{"copilot":"/opt/homebrew/bin/copilot","cwd":"/tmp/vuota","#
            + #""effort":"high","id":"c1","model":"gpt-6","prompt":"Ciao","type":"copilotQuestion","v":4}"# + "\n")
    }

    @Test func copilotModelsSkipAnEffortBuboDoesNotKnow() throws {
        let line = #"{"v":4,"type":"copilotModels","id":"m1","models":[{"id":"gpt-6","name":"GPT-6","multiplier":1,"#
            + #""supportedEfforts":["low","ultra"],"defaultEffort":"ultra"},{"id":"grok-5","name":"Grok 5"}]}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == .copilotModels(id: "m1", [
            CopilotModel(id: "gpt-6", name: "GPT-6", multiplier: 1, supportedEfforts: [.low]),
            CopilotModel(id: "grok-5", name: "Grok 5"),
        ]))
    }

    @Test func askWithAnEnvironmentCarriesIt() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"),
                                         settingSources: [], environment: ["PORT": "40000"]).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","env":{"PORT":"40000"},"id":"a1","prompt":"Ciao","settingSources":[],"type":"ask","v":4}"# + "\n")
    }

    @Test func askWithARosaCarriesItsNames() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"),
                                         settingSources: [], rosa: ["lente", "parentesi"]).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","orb":["lente","parentesi"],"prompt":"Ciao","settingSources":[],"type":"ask","v":4}"# + "\n")
    }

    @Test func askWithAServerOffersTheAnteprima() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"),
                                         settingSources: [], offersPreview: true).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","preview":true,"prompt":"Ciao","settingSources":[],"type":"ask","v":4}"# + "\n")
    }

    @Test func offerPreviewNamesTheConversation() throws {
        let line = try BridgeCommand.offerPreview(id: "a1", isOffered: false).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"available":false,"id":"a1","type":"previewServer","v":4}"# + "\n")
    }

    @Test func answerPreviewCarriesTextImageOrFailure() throws {
        let text = try BridgeCommand.answerPreview(call: "c1", .text("ok")).line()
        #expect(String(decoding: text, as: UTF8.self) == #"{"call":"c1","text":"ok","type":"previewResult","v":4}"# + "\n")
        let image = try BridgeCommand.answerPreview(call: "c1", .image(Data([0xFF, 0xD8]))).line()
        #expect(String(decoding: image, as: UTF8.self) == #"{"call":"c1","image":"/9g=","type":"previewResult","v":4}"# + "\n")
        let failure = try BridgeCommand.answerPreview(call: "c1", .failure("no")).line()
        #expect(String(decoding: failure, as: UTF8.self) == #"{"call":"c1","error":"no","type":"previewResult","v":4}"# + "\n")
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
        let line = #"{"v":4,"type":"previewCall","id":"a1","call":"c1","# + fields + "}"
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8))
            == .previewCall(id: "a1", call: "c1", action))
    }

    @Test func aPreviewCallBuboDoesNotKnowHasNoAction() throws {
        let line = #"{"v":4,"type":"previewCall","id":"a1","call":"c1","tool":"cancella"}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == .previewCall(id: "a1", call: "c1", nil))
        let missing = #"{"v":4,"type":"previewCall","id":"a1","call":"c1","tool":"clicca"}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(missing.utf8)) == .previewCall(id: "a1", call: "c1", nil))
    }

    @Test func cancelNamesTheConversation() throws {
        let line = try BridgeCommand.cancel(id: "a1").line()
        #expect(String(decoding: line, as: UTF8.self) == #"{"id":"a1","type":"cancel","v":4}"# + "\n")
    }

    @Test func foundCarriesTheSearchResult() throws {
        let line = try BridgeCommand.found(id: "s1", text: "/a.md").line()
        #expect(String(decoding: line, as: UTF8.self) == #"{"id":"s1","text":"/a.md","type":"found","v":4}"# + "\n")
    }

    @Test func readQuotaAsksWithoutAConversation() throws {
        let line = try BridgeCommand.readQuota.line()
        #expect(String(decoding: line, as: UTF8.self) == #"{"type":"quota","v":4}"# + "\n")
    }

    @Test func inspectCarriesTheFolderAndItsSources() throws {
        let line = try BridgeCommand.inspect(id: "c1", directory: URL(filePath: "/tmp/w"), settingSources: ["user"],
                                             projectConfigRoot: URL(filePath: "/tmp/repo/")).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/w","id":"c1","projectConfigRoot":"/tmp/repo","settingSources":["user"],"type":"config","v":4}"# + "\n")
    }

    @Test func warmCarriesTheSourcesAndCoolNothing() throws {
        let warm = try BridgeCommand.warmConfiguration(settingSources: ["user", "project", "local"],
                                                       projectConfigRoot: URL(filePath: "/tmp/repo/")).line()
        #expect(String(decoding: warm, as: UTF8.self)
            == #"{"projectConfigRoot":"/tmp/repo","settingSources":["user","project","local"],"type":"warm","v":4}"# + "\n")
        #expect(String(decoding: try BridgeCommand.coolConfiguration.line(), as: UTF8.self) == #"{"type":"cool","v":4}"# + "\n")
    }

    @Test func askResumingAConversationCarriesIt() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [],
                                         resuming: "c-1").line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","prompt":"Ciao","resume":"c-1","settingSources":[],"type":"ask","v":4}"# + "\n")
    }

    @Test func askContinuingFromAMessageCarriesTheCut() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [],
                                         resuming: "c-1", resumingAt: "m-2").line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","prompt":"Ciao","resume":"c-1","settingSources":[],"type":"ask","upTo":"m-2","v":4}"# + "\n")
    }

    @Test func readHistoryAsksForTheFirstPageOrAll() throws {
        #expect(String(decoding: try BridgeCommand.readHistory(id: "h1", isComplete: false).line(), as: UTF8.self)
            == #"{"all":false,"id":"h1","type":"history","v":4}"# + "\n")
        #expect(String(decoding: try BridgeCommand.readTranscript(id: "t1", conversation: "c-1").line(), as: UTF8.self)
            == #"{"conversation":"c-1","id":"t1","type":"transcript","v":4}"# + "\n")
        let complete = try BridgeCommand.readTranscript(id: "t1", conversation: "c-1", isComplete: true).line()
        #expect(String(decoding: complete, as: UTF8.self)
            == #"{"all":true,"conversation":"c-1","id":"t1","type":"transcript","v":4}"# + "\n")
    }

    @Test func askKeepingAConversationCarriesItsId() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [],
                                         keeping: "k-1").line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","keep":"k-1","prompt":"Ciao","settingSources":[],"type":"ask","v":4}"# + "\n")
    }

    @Test func theProfiloAndTheRegoleGoWithTheAskAsBrain() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [],
                                         secondBrain: "## Bubo/Profilo.md").line()
        #expect(String(decoding: line, as: UTF8.self)
            == ###"{"brain":"## Bubo/Profilo.md","cwd":"/tmp/x","id":"a1","prompt":"Ciao","settingSources":[],"type":"ask","v":4}"###
            + "\n")
    }

    @Test func onlyAnAskThatRemembersCarriesRemember() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [],
                                         remembers: true).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","prompt":"Ciao","remember":true,"settingSources":[],"type":"ask","v":4}"# + "\n")
        let plain = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [])
            .line()
        #expect(!String(decoding: plain, as: UTF8.self).contains("remember"))
    }

    @Test func theCopiesAreKeptAndForgottenByCommand() throws {
        #expect(String(decoding: try BridgeCommand.keepHistory(id: "k1").line(), as: UTF8.self)
            == #"{"id":"k1","type":"keep","v":4}"# + "\n")
        #expect(String(decoding: try BridgeCommand.forget(conversations: ["c-1", "c-2"]).line(), as: UTF8.self)
            == #"{"conversations":["c-1","c-2"],"type":"forget","v":4}"# + "\n")
        #expect(String(decoding: try BridgeCommand.forgetHistory(id: "f1").line(), as: UTF8.self)
            == #"{"id":"f1","type":"forgetHistory","v":4}"# + "\n")
    }

    @Test func theCopyEventsDecode() throws {
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(#"{"v":4,"type":"kept","id":"k1","count":4}"#.utf8))
            == .kept(id: "k1", count: 4))
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(#"{"v":4,"type":"forgot","id":"f1"}"#.utf8))
            == .forgot(id: "f1"))
    }

    @Test func theHistoryAndATranscriptDecode() throws {
        let history = #"""
            {"v":4,"type":"history","id":"h1","conversations":[
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
            {"v":4,"type":"transcript","id":"t1","messages":[{"role":"user","text":"Ciao"},{"role":"assistant","text":"Eccomi"}]}
            """#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(transcript.utf8)) == .transcript(id: "t1", [
            CLIConversation.Message(isFromUser: true, text: "Ciao"), CLIConversation.Message(isFromUser: false, text: "Eccomi"),
        ]))
        let dated = #"""
            {"v":4,"type":"transcript","id":"t1","messages":[{"id":"m1","role":"user","text":"Ciao","date":1790846145117}]}
            """#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(dated.utf8)) == .transcript(id: "t1", [
            CLIConversation.Message(id: "m1", isFromUser: true, text: "Ciao", date: Date(timeIntervalSince1970: 1_790_846_145.117)),
        ]))
    }

    @Test func theConfigurationDecodes() throws {
        let line = #"""
            {"v":4,"type":"config","id":"c1","skills":["prova"],"plugins":[{"name":"figma","version":"1.2.0","path":"/p/figma"},{"name":"locale"}],
             "pluginErrors":[{"plugin":"rotto@mercato","type":"dependency-unsatisfied","message":"manca base"}],
             "mcpServers":[{"name":"db","status":"failed","source":"project","error":"Connection closed"},{"name":"linear","status":"needs-auth"}],
             "instructions":[{"path":"/r/CLAUDE.md","type":"Project"}],
             "agents":[{"name":"Explore","description":"Cerca","model":"haiku"},{"name":"revisore","description":"Rivede"}]}
            """#
        let expected = ClaudeConfiguration(
            skills: ["prova"],
            plugins: [.init(name: "figma", version: "1.2.0", path: "/p/figma"), .init(name: "locale", version: nil)],
            pluginErrors: [.init(plugin: "rotto@mercato", message: "manca base", type: "dependency-unsatisfied")],
            mcpServers: [.init(name: "db", status: "failed", source: "project", error: "Connection closed"),
                         .init(name: "linear", status: "needs-auth", source: nil, error: nil)],
            instructions: [.init(path: "/r/CLAUDE.md", type: "Project")],
            agents: [.init(name: "Explore", description: "Cerca", model: "haiku"),
                     .init(name: "revisore", description: "Rivede", model: nil)])
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == .configuration(id: "c1", expected))
    }

    @Test(arguments: [
        (#"{"v":4,"type":"ready"}"#, BridgeEvent.ready),
        (#"{"v":4,"type":"text","id":"a1","text":"ci"}"#, .text(id: "a1", text: "ci")),
        (#"{"v":4,"type":"done","id":"a1"}"#, .done(id: "a1")),
        (#"{"v":4,"type":"state","id":"a1","state":"requires_action"}"#, .progress(id: "a1", .state(.requiresAction))),
        (#"{"v":4,"type":"summary","id":"a1","text":"Leggo i file"}"#, .progress(id: "a1", .summary("Leggo i file"))),
        (#"{"v":4,"type":"variante","id":"a1","nome":"lente"}"#, .progress(id: "a1", .variante("lente"))),
        (#"{"v":4,"type":"edit","id":"a1","file":"/w/a.swift","lines":["g()"]}"#,
         .progress(id: "a1", .edit(file: "/w/a.swift", lines: ["g()"]))),
        (#"{"v":4,"type":"read","id":"a1","files":["/w/a.swift","/w/b.swift"]}"#,
         .progress(id: "a1", .read(files: ["/w/a.swift", "/w/b.swift"]))),
        (#"{"v":4,"type":"ran","id":"a1"}"#, .progress(id: "a1", .ranCommand)),
        (#"{"v":4,"type":"error","id":"a1","message":"no"}"#, .error(id: "a1", message: "no")),
        (#"{"v":4,"type":"error","message":"no"}"#, .error(id: nil, message: "no")),
        (#"{"v":4,"type":"error","id":"a1","message":"Credit balance is too low","reason":"billing_error"}"#,
         .turnFailed(id: "a1", TurnFailure(message: "Credit balance is too low", reason: "billing_error"))),
        (#"{"v":4,"type":"error","id":"a1","message":"no","reason":"server_error","status":529,"noResponse":true}"#,
         .turnFailed(id: "a1", TurnFailure(message: "no", reason: "server_error", status: 529, hadNoResponse: true))),
        (#"{"v":4,"type":"error","message":"no","reason":"unknown"}"#, .error(id: nil, message: "no")),
        (#"{"v":4,"type":"search","id":"s1","query":"ci","project":"/p"}"#, .search(id: "s1", query: "ci", project: "/p")),
        (#"{"v":4,"type":"search","id":"s1","query":"ci"}"#, .search(id: "s1", query: "ci", project: nil)),
        (#"{"v":4,"type":"search","id":"s1","query":"ci","source":"secondo-cervello"}"#,
         .search(id: "s1", query: "ci", project: nil, source: .secondBrain)),
        (#"{"v":4,"type":"search","id":"s1","query":"ci","source":"altrove"}"#, .search(id: "s1", query: "ci", project: nil)),
        (#"{"v":4,"type":"remember","id":"r1","title":"Ombrello","text":"portarlo"}"#,
         .remember(id: "r1", NoteRequest(title: "Ombrello", text: "portarlo"))),
        (#"{"v":4,"type":"remember","id":"r2","conversation":"a1","mode":"riscrivi","note":"Diario/oggi.md","text":"x","confirmed":true}"#,
         .remember(id: "r2", NoteRequest(mode: .replace, note: "Diario/oggi.md", text: "x", isConfirmed: true),
                   conversation: "a1")),
        (#"{"v":4,"type":"quota","fiveHour":{"used":0.19,"resetsAt":1790852400.5},"sevenDay":{"used":0.02,"resetsAt":1791428400}}"#,
         .quota(Quota(fiveHour: Quota.Window(used: 0.19, resetsAt: Date(timeIntervalSince1970: 1_790_852_400.5)),
                      sevenDay: Quota.Window(used: 0.02, resetsAt: Date(timeIntervalSince1970: 1_791_428_400))))),
        (#"{"v":4,"type":"quota","sevenDay":{"used":0.8,"resetsAt":1791428400}}"#,
         .quota(Quota(sevenDay: Quota.Window(used: 0.8, resetsAt: Date(timeIntervalSince1970: 1_791_428_400))))),
        (#"{"v":4,"type":"limit","id":"a1","window":"five_hour","resetsAt":1790852400}"#,
         .limit(id: "a1", reached: Quota.Limit(window: "five_hour", resetsAt: Date(timeIntervalSince1970: 1_790_852_400)))),
        (#"{"v":4,"type":"limit","id":"a1"}"#, .limit(id: "a1", reached: Quota.Limit())),
        (#"{"v":4,"type":"signInRequired","id":"a1"}"#, .signInRequired(id: "a1")),
        (#"{"v":4,"type":"permissionWithdrawn","id":"a1","request":"p1"}"#, .permissionWithdrawn(id: "a1", request: "p1")),
        (#"{"v":5,"type":"whatever"}"#, .unsupportedVersion(5)),
    ])
    func eventsDecode(line: String, event: BridgeEvent) throws {
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == event)
    }

    @Test func anUnknownEventDoesNotDecode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BridgeEvent.self, from: Data(#"{"v":4,"type":"boh"}"#.utf8))
        }
    }

    @Test func anAnswerToAPermissionIsAllowOrDeny() throws {
        #expect(String(decoding: try BridgeCommand.answerPermission(request: "p1", allows: true).line(), as: UTF8.self)
            == #"{"behavior":"allow","request":"p1","type":"permission","v":4}"# + "\n")
        #expect(String(decoding: try BridgeCommand.answerPermission(request: "p1", allows: false).line(), as: UTF8.self)
            == #"{"behavior":"deny","request":"p1","type":"permission","v":4}"# + "\n")
    }

    @Test func aPermissionRequestDecodes() throws {
        let line = #"{"v":4,"type":"permission","id":"a1","request":"p1","tool":"Bash","command":"git push -f","#
            + #""title":"Claude wants to run git push -f","description":"Push","fromSubagent":true,"suppressAlwaysAllowRule":true}"#
        var request = PermissionRequest(id: "p1", tool: "Bash", command: "git push -f")
        request.title = "Claude wants to run git push -f"
        request.detail = "Push"
        request.isFromSubagent = true
        request.suppressesRule = true
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == .permission(id: "a1", request))
    }
}

extension BridgeMessageTests {
    // Criterio 1: il turno di un'Esecuzione porta le sue Regole e dice al ponte che nessuno risponde.
    @Test func anUnattendedAskCarriesItsRulesAndNoPrompts() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [],
                                         unattended: UnattendedTurn(rules: ["Bash(npm test)"])).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","prompt":"Ciao","settingSources":[],"type":"ask","unattended":{"rules":["Bash(npm test)"]},"v":4}"# + "\n")
    }

    // #174: l'Esecuzione con un agente lo passa al ponte, che lo dà a `claude` come `Options.agent`.
    @Test func anUnattendedAskCarriesItsAgent() throws {
        let line = try BridgeCommand.ask(id: "a1", prompt: "Ciao", directory: URL(filePath: "/tmp/x"), settingSources: [],
                                         unattended: UnattendedTurn(agent: "revisore")).line()
        #expect(String(decoding: line, as: UTF8.self)
            == #"{"cwd":"/tmp/x","id":"a1","prompt":"Ciao","settingSources":[],"type":"ask","unattended":{"agent":"revisore","rules":[]},"v":4}"# + "\n")
    }

    // #174: la Richiesta di un subagent porta il suo nome.
    @Test func aSubagentsPermissionRequestCarriesItsName() throws {
        let line = #"{"v":4,"type":"permission","id":"a1","request":"p1","tool":"Bash","command":"ls","fromSubagent":true,"agent":"revisore"}"#
        var request = PermissionRequest(id: "p1", tool: "Bash", command: "ls")
        request.isFromSubagent = true
        request.agent = "revisore"
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(line.utf8)) == .permission(id: "a1", request))
    }

    @Test func aDenialAndTheChosenModeArriveAsProgress() throws {
        let denial = #"{"v":4,"type":"denial","id":"a1","toolUseID":"t1","tool":"Bash","command":"npm test","suggestions":["Bash(npm test)"],"source":"sdk"}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(denial.utf8))
            == .progress(id: "a1", .denial(BridgeDenial(id: "t1", tool: "Bash", command: "npm test",
                                                        suggestions: ["Bash(npm test)"], source: .sdk))))
        let mode = #"{"v":4,"type":"mode","id":"a1","permissionMode":"default"}"#
        #expect(try JSONDecoder().decode(BridgeEvent.self, from: Data(mode.utf8)) == .progress(id: "a1", .permissionMode("default")))
    }
}
