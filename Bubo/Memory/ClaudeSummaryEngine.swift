import Foundation

/// Claude with the light model of the router, in one turn with no tools, no settings and no copy of the conversation.
///
/// The Sessione's messages already went to Claude: no new recipient.
struct ClaudeSummaryEngine: SummaryEngine {
    /// The most characters of conversation Claude reads: the latest ones.
    static let characterLimit = 40_000

    /// The bridge to `claude`, started if needed.
    let bridge: () async throws -> AgentBridge
    /// The model alias; `nil` for the user's own choice.
    var model: String? = ModelRouter.defaultChoice(for: .summary).0.alias
    /// Receives the tokens and the figure of a summary, each time `claude` reports them, with its Sessione and the
    /// summary's own turn id, `riassunto-<uuid>`.
    var usage: (_ usage: TurnUsage, _ session: UUID, _ turn: String) -> Void = { _, _, _ in }

    var needsNetwork: Bool { true }

    func summary(of input: SummaryInput) async throws -> SessionSummary {
        let agent = try await bridge()
        let turn = "riassunto-\(UUID().uuidString)"
        var answer = ""
        for try await text in agent.summarize(input.trimmed(toCharacters: Self.characterLimit).prompt, model: model,
                                              usage: { [usage] in usage($0, input.session, turn) }) {
            answer += text
        }
        let summary = SessionSummary(markdown: answer)
        guard !summary.isEmpty else { throw SummaryEngineError.emptyAnswer }
        return summary
    }
}
