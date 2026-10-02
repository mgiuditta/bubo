import FoundationModels

/// Apple's on-device model as the router uses it: one place for availability, token counts and sessions.
///
/// It is `SystemLanguageModel.default`, which runs on the Mac; never Private Cloud Compute. The answer of a Domanda
/// (#89) uses it, and the two-step classifier of #381 can too.
nonisolated struct OnDeviceModel: Sendable {
    /// What the Allegati of a Domanda may take: half of the 4,096-token context, the rest to the instructions, the
    /// question and the answer.
    static let attachmentLimit = 2_000

    let model: SystemLanguageModel
    /// How long a count may take before it is given up: the classification's budget, so it never delays the decision.
    let countBudget: Duration
    private let availability: @Sendable () -> Bool
    private let counter: @Sendable (String) async throws -> Int?

    /// Creates the router's view of `model`.
    ///
    /// - Parameters:
    ///   - isAvailable: Whether the model can run now; the model's own availability when `nil`.
    ///   - tokenCount: Counts the tokens of a text; `SystemLanguageModel.tokenCount(for:)` when `nil`, which answers
    ///     `nil` before macOS 26.4.
    init(model: SystemLanguageModel = .default, countBudget: Duration = .milliseconds(300),
         isAvailable: (@Sendable () -> Bool)? = nil,
         tokenCount: (@Sendable (String) async throws -> Int?)? = nil) {
        self.model = model
        self.countBudget = countBudget
        availability = isAvailable ?? { model.availability == .available }
        counter = tokenCount ?? { text in
            guard #available(macOS 26.4, *) else { return nil }
            return try await model.tokenCount(for: text)
        }
    }

    /// Whether the model can run now: Apple Intelligence on, the Mac eligible, the model downloaded.
    var isAvailable: Bool {
        availability()
    }

    /// Whether `content` fits in `limit` tokens: counted by the model itself, never estimated from its characters.
    ///
    /// A count that fails or runs past `countBudget` is `.notMeasurable`.
    @concurrent func fit(of content: String, within limit: Int = attachmentLimit) async -> OnDeviceFit {
        guard isAvailable else { return .unavailable }
        return await withTaskGroup(of: OnDeviceFit.self) { group in
            group.addTask { [counter] in
                guard let tokens = try? await counter(content) else { return .notMeasurable }
                return tokens <= limit ? .fits(tokens: tokens) : .tooLong(tokens: tokens)
            }
            group.addTask { [countBudget] in
                try? await Task.sleep(for: countBudget)
                return .notMeasurable
            }
            let first = await group.next() ?? .notMeasurable
            group.cancelAll()
            return first
        }
    }

    /// A new session with `instructions`: one per request, so no transcript grows into the context.
    func makeSession(instructions: String) -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: instructions)
    }
}
