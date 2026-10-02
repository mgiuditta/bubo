import Foundation
import FoundationModels

/// Apple's on-device model, for a Riassunto di Sessione without network.
///
/// Only `SystemLanguageModel.default`, which runs on the Mac: never Private Cloud Compute. Its context holds 4,096
/// tokens, so only the latest messages of a long Sessione are read.
struct FoundationModelsSummaryEngine: SummaryEngine {
    /// The most characters of conversation the model reads: about 2,000 tokens, leaving room to the answer.
    static let characterLimit = 6_000

    private let model: SystemLanguageModel

    /// Creates the engine on `model`.
    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    var needsNetwork: Bool { false }

    /// Whether the model can run now: Apple Intelligence on, the Mac eligible and the model downloaded.
    var isAvailable: Bool { model.availability == .available }

    func summary(of input: SummaryInput) async throws -> SessionSummary {
        guard isAvailable else { throw SummaryEngineError.unavailable }
        let session = LanguageModelSession(model: model, instructions: SummaryInput.instructions)
        let draft = try await session.respond(to: input.trimmed(toCharacters: Self.characterLimit).transcript,
                                              generating: SummaryDraft.self).content
        let summary = SessionSummary(done: Self.items(draft.fatto), decisions: Self.items(draft.decisioni),
                                     open: Self.items(draft.aperto))
        guard !summary.isEmpty else { throw SummaryEngineError.emptyAnswer }
        return summary
    }

    func shortText(for prompt: String, following instructions: String, session: UUID) async throws -> String {
        guard isAvailable else { throw SummaryEngineError.unavailable }
        let answer = try await LanguageModelSession(model: model, instructions: instructions)
            .respond(to: String(prompt.prefix(Self.characterLimit))).content
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SummaryEngineError.emptyAnswer
        }
        return answer
    }

    /// The items on one line each, without the empty ones.
    private static func items(_ texts: [String]) -> [String] {
        texts.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }.filter { !$0.isEmpty }
    }
}
