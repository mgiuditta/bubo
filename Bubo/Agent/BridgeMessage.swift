import Foundation

/// The JSON-lines protocol between Bubo and the agent bridge (`bridge/src/main.ts`).
///
/// Every line carries `v`; both sides refuse a version they do not speak.
enum BridgeProtocol {
    /// The version both sides speak.
    static let version = 4
}

/// A command Bubo writes to the bridge, one JSON object per line.
enum BridgeCommand: Equatable {
    /// Starts a conversation with `claude` in `directory`, answering `prompt`, loading only `settingSources`.
    ///
    /// When `directory` is a worktree, `projectConfigRoot` is its main checkout, where `claude` reads the
    /// Progetto's settings, `.mcp.json` and `.claude/`. `model` is an alias of `claude`, such as `sonnet`;
    /// without it, the model the user chose in `claude` answers. `environment` adds to the one `claude` gets.
    /// `resuming` is a conversation of the Cronologia CLI the answer continues, always as a fork; `resumingAt` is the
    /// message of `resuming` the fork stops at, included (Continua da qui); without it, the whole conversation.
    /// `keeping` is the id of the agent's conversation, given by Bubo, to copy in Bubo's database (ADR 0006);
    /// without it nothing of the conversation is written. `sandbox` runs the commands of `claude` in the Sandbox;
    /// without it they run as the user's. `offersPreview` starts the conversation with the Anteprima's tools, when the
    /// Sessione already has a server. `teamRules` are the Progetto's Risorse di squadra in force,
    /// passed as session rules: `allow` as `allowedTools`, `deny` as `disallowedTools`, `ask` in `settings`.
    /// `remembers` gives `claude` the `ricorda` tool, only in a Domanda. `permissionMode` is how `claude` approves the
    /// calls; without it, `claude` picks the mode itself. `effort` is the router's effort; without it, the model's default.
    /// `rosa` names the Varianti the agent may give the Orb with `⟦orb:nome⟧`; without it, the agent gets no
    /// instruction and the Orb follows only its tools. `unattended` makes it a turn with nobody in front of it, the one
    /// of an Esecuzione: no Richiesta di permesso, its rules as session rules, and a `denial` for each action denied.
    case ask(id: String, prompt: String, directory: URL, settingSources: [String], projectConfigRoot: URL? = nil,
             model: String? = nil, environment: [String: String] = [:], resuming: String? = nil, resumingAt: String? = nil,
             keeping: String? = nil, sandbox: SandboxPolicy? = nil, offersPreview: Bool = false, teamRules: TeamRules = TeamRules(),
             remembers: Bool = false, permissionMode: PermissionMode? = nil, effort: Effort? = nil, rosa: [String] = [],
             unattended: UnattendedTurn? = nil)
    /// Interrupts the conversation `id`.
    case cancel(id: String)
    /// Answers the call `id` of the `cerca` or `ricorda` tool with its result.
    case found(id: String, text: String)
    /// Reads the Quota without a Domanda; the bridge answers with `quota` only if it has one.
    case readQuota
    /// Reads the configuration `claude` loads in `directory` with `settingSources`, without a turn of the model.
    case inspect(id: String, directory: URL, settingSources: [String], projectConfigRoot: URL? = nil)
    /// Keeps one `claude` ready for `inspect` with the same `settingSources` and `projectConfigRoot` (#311): started
    /// now, without a turn of the model, and used once by the next matching `inspect`; another one replaces it.
    case warmConfiguration(settingSources: [String], projectConfigRoot: URL? = nil)
    /// Closes the `claude` kept ready by `warmConfiguration`, if any.
    case coolConfiguration
    /// Lists the Cronologia CLI, most recent first: the first page, or all of it when `isComplete`.
    case readHistory(id: String, isComplete: Bool)
    /// Reads the latest messages of `conversation`, or all of them when `isComplete`, for the Indice.
    case readTranscript(id: String, conversation: String, isComplete: Bool = false)
    /// Answers the Richiesta di permesso `request`: the call runs only when `allows`. `isLasting` says the user allowed
    /// it for the rest of the Sessione: a host outside the Sandbox then comes with its session rule
    /// `WebFetch(domain:)`.
    case answerPermission(request: String, allows: Bool, isLasting: Bool = false)
    /// Lists the Regole di permesso of `claude` in `directory` that widen the Sandbox, without a turn of the model.
    case readSandboxRules(id: String, directory: URL, settingSources: [String], projectConfigRoot: URL? = nil)
    /// Answers the gate's question `request`: whether the call is level 4 or 5, so that it asks anyway.
    case answerRisk(request: String, isDangerous: Bool)
    /// Copies in Bubo's database the conversations of the Cronologia CLI not copied yet, or changed since.
    case keepHistory(id: String)
    /// Deletes the copies of `conversations`.
    case forget(conversations: [String])
    /// Deletes the copies of the Cronologia CLI.
    case forgetHistory(id: String)
    /// Adds the Anteprima's tools to the conversation `id` in progress, or removes them, as its server comes or goes.
    case offerPreview(id: String, isOffered: Bool)
    /// Answers the call `call` to a tool of the Anteprima.
    case answerPreview(call: String, PreviewReply)
    /// Asks `model` to answer `prompt` in one turn in the empty `directory`, with no tools, no settings and no copy of
    /// the conversation: the Riassunto di Sessione. The answer comes as for `ask`.
    case summarize(id: String, prompt: String, directory: URL, model: String?)

    /// The command as one line of JSON, newline included.
    func line() throws -> Data {
        var object: [String: Any]
        switch self {
        case let .ask(id, prompt, directory, settingSources, projectConfigRoot, model, environment, resuming, resumingAt,
                      keeping, sandbox, offersPreview, teamRules, remembers, permissionMode, effort, rosa, unattended):
            object = ["type": "ask", "id": id, "prompt": prompt, "cwd": directory.path, "settingSources": settingSources]
            object["projectConfigRoot"] = projectConfigRoot?.path
            object["model"] = model
            if !environment.isEmpty { object["env"] = environment }
            object["resume"] = resuming
            if resuming != nil { object["upTo"] = resumingAt }
            object["keep"] = keeping
            object["sandbox"] = sandbox?.jsonObject
            if offersPreview { object["preview"] = true }
            if teamRules != TeamRules() {
                object["rules"] = ["allow": teamRules.allow, "deny": teamRules.deny, "ask": teamRules.ask]
            }
            if remembers { object["remember"] = true }
            object["permissionMode"] = permissionMode?.rawValue
            object["effort"] = effort?.rawValue
            if !rosa.isEmpty { object["orb"] = rosa }
            if let unattended { object["unattended"] = ["rules": unattended.rules] }
        case let .cancel(id):
            object = ["type": "cancel", "id": id]
        case let .found(id, text):
            object = ["type": "found", "id": id, "text": text]
        case .readQuota:
            object = ["type": "quota"]
        case let .inspect(id, directory, settingSources, projectConfigRoot):
            object = ["type": "config", "id": id, "cwd": directory.path, "settingSources": settingSources]
            object["projectConfigRoot"] = projectConfigRoot?.path
        case let .warmConfiguration(settingSources, projectConfigRoot):
            object = ["type": "warm", "settingSources": settingSources]
            object["projectConfigRoot"] = projectConfigRoot?.path
        case .coolConfiguration:
            object = ["type": "cool"]
        case let .readHistory(id, isComplete):
            object = ["type": "history", "id": id, "all": isComplete]
        case let .readTranscript(id, conversation, isComplete):
            object = ["type": "transcript", "id": id, "conversation": conversation]
            if isComplete { object["all"] = true }
        case let .answerPermission(request, allows, isLasting):
            object = ["type": "permission", "request": request, "behavior": allows ? "allow" : "deny"]
            if allows && isLasting { object["scope"] = "session" }
        case let .readSandboxRules(id, directory, settingSources, projectConfigRoot):
            object = ["type": "sandboxRules", "id": id, "cwd": directory.path, "settingSources": settingSources]
            object["projectConfigRoot"] = projectConfigRoot?.path
        case let .answerRisk(request, isDangerous):
            object = ["type": "risk", "request": request, "dangerous": isDangerous]
        case let .keepHistory(id):
            object = ["type": "keep", "id": id]
        case let .forget(conversations):
            object = ["type": "forget", "conversations": conversations]
        case let .forgetHistory(id):
            object = ["type": "forgetHistory", "id": id]
        case let .offerPreview(id, isOffered):
            object = ["type": "previewServer", "id": id, "available": isOffered]
        case let .summarize(id, prompt, directory, model):
            object = ["type": "summarize", "id": id, "prompt": prompt, "cwd": directory.path]
            object["model"] = model
        case let .answerPreview(call, reply):
            object = ["type": "previewResult", "call": call]
            switch reply {
            case let .text(text): object["text"] = text
            case let .image(jpeg): object["image"] = jpeg.base64EncodedString()
            case let .failure(message): object["error"] = message
            }
        }
        object["v"] = BridgeProtocol.version
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}

/// An event the bridge writes to Bubo, one JSON object per line.
enum BridgeEvent: Equatable, Decodable {
    /// The bridge is listening.
    case ready
    /// More of the answer to `id`.
    case text(id: String, text: String)
    /// The answer to `id` is complete.
    case done(id: String)
    /// What the conversation `id` is doing, or its latest summary.
    case progress(id: String, AgentProgress)
    /// The conversation `id`, or the bridge itself when `id` is `nil`, failed.
    case error(id: String?, message: String)
    /// The conversation `id` failed, with the SDK's reasons besides the text.
    case turnFailed(id: String, TurnFailure)
    /// The conversation `id` stopped at a subscription limit.
    case limit(id: String, reached: Quota.Limit)
    /// The conversation `id` stopped because the login of `claude` is no longer valid.
    case signInRequired(id: String)
    /// The conversation `id` did not start: its Sandbox could not, for `reason`, as `claude` wrote it.
    case sandboxUnavailable(id: String, reason: String)
    /// The `claude` of the conversation `id`, from its `init`: its version and the capabilities Bubo knows.
    case claude(id: String, version: String, capabilities: Set<ClaudeCapability>)
    /// The conversation `id` stopped before the model's turn: its `claude` is older than the minimum, or than the one
    /// Anthropic requires; `version` is `nil` when `claude` did not say it.
    case outdated(id: String, version: String?)
    /// `claude` called `cerca`: search the Indice for `query`, only in the memory of `project` and only in `source`
    /// when given. `conversation` is the answer that called it, for its line Richiamato.
    case search(id: String, query: String, project: String?, source: SearchSource? = nil, conversation: String? = nil)
    /// The conversation `id` called a tool of the Anteprima: do `action`, `nil` for a tool Bubo does not know, and
    /// answer `call`.
    case previewCall(id: String, call: String, PreviewAction?)
    /// `claude` called `ricorda`: save `text` as a note titled `title` in the Secondo cervello.
    case remember(id: String, title: String, text: String)
    /// The Quota windows `claude` reported; a window it did not report is `nil`.
    case quota(Quota)
    /// The configuration `claude` loads, asked by `inspect` `id`.
    case configuration(id: String, ClaudeConfiguration)
    /// The Cronologia CLI, asked by `readHistory` `id`.
    case history(id: String, [CLIConversation])
    /// The messages of a conversation, asked by `readTranscript` `id`.
    case transcript(id: String, [CLIConversation.Message])
    /// `count` conversations of the Cronologia CLI copied, asked by `keepHistory` `id`.
    case kept(id: String, count: Int)
    /// The copies of the Cronologia CLI are gone, asked by `forgetHistory` `id`.
    case forgot(id: String)
    /// The conversation `id` waits for the user to answer a Richiesta di permesso.
    case permission(id: String, PermissionRequest)
    /// The conversation `id` no longer waits for the Richiesta `request`.
    case permissionWithdrawn(id: String, request: String)
    /// The gate of the conversation `id` asks whether a call, described as a Richiesta, is level 4 or 5.
    case risk(id: String, PermissionRequest)
    /// The tokens and the figure of the conversation `id` so far; each one replaces the one before.
    case usage(id: String, TurnUsage)
    /// The model that answered the conversation `id` and its effective effort, just before it ends.
    case answeredBy(id: String, AnsweringModel)
    /// The Claude models the account offers, read with the Quota.
    case models(ModelCatalog)
    /// The Regole di permesso that widen the Sandbox, answering the request `id`.
    case sandboxRules(id: String, [SandboxWideningRule])
    /// A line in a protocol version Bubo does not speak.
    case unsupportedVersion(Int)

    private enum CodingKeys: String, CodingKey {
        case v, type, id, text, state, message, query, project, source, title, fiveHour, sevenDay, window, resetsAt,
             conversations, messages, request, file, lines, count, reason, call, tool, selector, url, filter, code, y,
             rules, conversation, before, after, mode, memories, files, status, noResponse, version, capabilities, model,
             effort, models, nome, permissionMode
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .v)
        guard version == BridgeProtocol.version else {
            self = .unsupportedVersion(version)
            return
        }
        switch try container.decode(String.self, forKey: .type) {
        case "ready": self = .ready
        case "text": self = .text(id: try container.decode(String.self, forKey: .id),
                                  text: try container.decode(String.self, forKey: .text))
        case "done": self = .done(id: try container.decode(String.self, forKey: .id))
        case "state": self = .progress(id: try container.decode(String.self, forKey: .id),
                                       .state(try container.decode(AgentProgress.State.self, forKey: .state)))
        case "summary": self = .progress(id: try container.decode(String.self, forKey: .id),
                                         .summary(try container.decode(String.self, forKey: .text)))
        case "edit": self = .progress(id: try container.decode(String.self, forKey: .id),
                                      .edit(file: try container.decode(String.self, forKey: .file),
                                            lines: try container.decode([String].self, forKey: .lines)))
        case "read": self = .progress(id: try container.decode(String.self, forKey: .id),
                                      .read(files: try container.decode([String].self, forKey: .files)))
        case "variante": self = .progress(id: try container.decode(String.self, forKey: .id),
                                          .variante(try container.decode(String.self, forKey: .nome)))
        case "ran": self = .progress(id: try container.decode(String.self, forKey: .id), .ranCommand)
        case "sandboxBlock": self = .progress(id: try container.decode(String.self, forKey: .id),
                                              .sandboxBlock(try SandboxBlock(from: decoder)))
        case "sandboxRules": self = .sandboxRules(id: try container.decode(String.self, forKey: .id),
                                                  try container.decode([SandboxWideningRule].self, forKey: .rules))
        case "remembered":
            self = .progress(id: try container.decode(String.self, forKey: .id),
                             .memory(.remembered(MemoryWrite(file: try container.decode(String.self, forKey: .file),
                                                             previous: try container.decodeIfPresent(String.self, forKey: .before),
                                                             written: try container.decodeIfPresent(String.self, forKey: .after)))))
        case "recalled":
            self = .progress(id: try container.decode(String.self, forKey: .id),
                             .memory(.recalled(MemoryRecall(
                                isSynthesis: try container.decode(String.self, forKey: .mode) == "synthesize",
                                memories: try container.decode([MemoryRecall.Memory].self, forKey: .memories)))))
        case "error":
            let id = try container.decodeIfPresent(String.self, forKey: .id)
            let failure = TurnFailure(message: try container.decode(String.self, forKey: .message),
                                      reason: try container.decodeIfPresent(String.self, forKey: .reason),
                                      status: try container.decodeIfPresent(Int.self, forKey: .status),
                                      hadNoResponse: try container.decodeIfPresent(Bool.self, forKey: .noResponse) ?? false)
            if let id, failure != TurnFailure(message: failure.message) {
                self = .turnFailed(id: id, failure)
            } else {
                self = .error(id: id, message: failure.message)
            }
        case "limit": self = .limit(id: try container.decode(String.self, forKey: .id),
                                    reached: Quota.Limit(window: try container.decodeIfPresent(String.self, forKey: .window),
                                                        resetsAt: try container.decodeIfPresent(Double.self, forKey: .resetsAt)
                                                            .map(Date.init(timeIntervalSince1970:))))
        case "signInRequired": self = .signInRequired(id: try container.decode(String.self, forKey: .id))
        case "sandboxUnavailable": self = .sandboxUnavailable(id: try container.decode(String.self, forKey: .id),
                                                              reason: try container.decode(String.self, forKey: .reason))
        case "claude": self = .claude(id: try container.decode(String.self, forKey: .id),
                                      version: try container.decode(String.self, forKey: .version),
                                      capabilities: ClaudeCapability.known(
                                          in: try container.decodeIfPresent([String].self, forKey: .capabilities)))
        case "outdated": self = .outdated(id: try container.decode(String.self, forKey: .id),
                                          version: try container.decodeIfPresent(String.self, forKey: .version))
        case "search": self = .search(id: try container.decode(String.self, forKey: .id),
                                      query: try container.decode(String.self, forKey: .query),
                                      project: try container.decodeIfPresent(String.self, forKey: .project),
                                      // A source Bubo does not know searches everywhere.
                                      source: try container.decodeIfPresent(String.self, forKey: .source)
                                          .flatMap(SearchSource.init(rawValue:)),
                                      conversation: try container.decodeIfPresent(String.self, forKey: .conversation))
        case "previewCall":
            self = .previewCall(id: try container.decode(String.self, forKey: .id),
                                call: try container.decode(String.self, forKey: .call),
                                PreviewAction(tool: try container.decode(String.self, forKey: .tool),
                                              selector: try container.decodeIfPresent(String.self, forKey: .selector),
                                              text: try container.decodeIfPresent(String.self, forKey: .text),
                                              url: try container.decodeIfPresent(String.self, forKey: .url),
                                              filter: try container.decodeIfPresent(String.self, forKey: .filter),
                                              code: try container.decodeIfPresent(String.self, forKey: .code),
                                              y: try container.decodeIfPresent(Double.self, forKey: .y)))
        case "remember": self = .remember(id: try container.decode(String.self, forKey: .id),
                                          title: try container.decode(String.self, forKey: .title),
                                          text: try container.decode(String.self, forKey: .text))
        case "quota": self = .quota(Quota(fiveHour: try container.decodeIfPresent(Quota.Window.self, forKey: .fiveHour),
                                          sevenDay: try container.decodeIfPresent(Quota.Window.self, forKey: .sevenDay)))
        case "config": self = .configuration(id: try container.decode(String.self, forKey: .id),
                                             try ClaudeConfiguration(from: decoder))
        case "history": self = .history(id: try container.decode(String.self, forKey: .id),
                                        try container.decode([CLIConversation].self, forKey: .conversations))
        case "transcript": self = .transcript(id: try container.decode(String.self, forKey: .id),
                                              try container.decode([CLIConversation.Message].self, forKey: .messages))
        case "kept": self = .kept(id: try container.decode(String.self, forKey: .id),
                                  count: try container.decode(Int.self, forKey: .count))
        case "forgot": self = .forgot(id: try container.decode(String.self, forKey: .id))
        case "permission": self = .permission(id: try container.decode(String.self, forKey: .id),
                                              try PermissionRequest(from: decoder))
        case "risk": self = .risk(id: try container.decode(String.self, forKey: .id), try PermissionRequest(from: decoder))
        case "permissionWithdrawn": self = .permissionWithdrawn(id: try container.decode(String.self, forKey: .id),
                                                                request: try container.decode(String.self, forKey: .request))
        case "usage": self = .usage(id: try container.decode(String.self, forKey: .id), try TurnUsage(from: decoder))
        case "answeredBy":
            self = .answeredBy(id: try container.decode(String.self, forKey: .id),
                               AnsweringModel(model: try container.decode(String.self, forKey: .model),
                                              // A level Bubo does not know yet shows no effort rather than a wrong one.
                                              effort: try container.decodeIfPresent(String.self, forKey: .effort)
                                                  .flatMap(Effort.init(rawValue:))))
        case "denial": self = .progress(id: try container.decode(String.self, forKey: .id), .denial(try BridgeDenial(from: decoder)))
        case "mode": self = .progress(id: try container.decode(String.self, forKey: .id),
                                      .permissionMode(try container.decode(String.self, forKey: .permissionMode)))
        case "models": self = .models(ModelCatalog(entries: try container.decode([ModelCatalog.Entry].self, forKey: .models)))
        case let type:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown event \(type)")
        }
    }
}
