/// Who may receive which Allegato, and how much of it (spec 09, Allegati e fornitori).
///
/// Claude reads every Allegato from its path or its text. A model on the Mac reads only text, so never a folder or an
/// image; whether the text fits Apple's model is measured apart (`OnDeviceFit`). Any other provider receives the text
/// of an Allegato, a PDF's included, only under its cap and, in a cloud, only after the user confirmed that Allegato.
nonisolated enum AttachmentPolicy {
    /// Who would receive an Allegato.
    enum Recipient: Sendable {
        /// `claude`, through the agent bridge.
        case claude
        /// Apple Foundation Models, on the Mac.
        case onDevice
        /// A provider other than Claude, such as an OpenAI-compatible endpoint, before the user confirmed anything.
        case otherProvider
    }

    /// What may go to an OpenAI-compatible endpoint of a Domanda's Allegati.
    enum Verdict: Equatable, Sendable {
        /// Every Allegato may go, as text in the prompt.
        case allowed
        /// The endpoint is in a cloud: these Allegati wait for the user's confirmation before a byte of them leaves.
        case needsConfirmation([Allegato])
        /// This Allegato has no text to send, such as a folder or an image: it goes only to Claude.
        case onlyClaude(Allegato)
        /// The Allegati's text is over the endpoint's cap: nothing is cut, Claude is proposed instead.
        case overCap(tokens: Int, cap: Int)
    }

    /// The cap of an endpoint that tells no context: tokens, for OpenAI, Gemini and custom endpoints.
    static let fixedCap = 32_000

    /// The characters counted as one token where no tokenizer exists: few, so the estimate errs on the long side.
    static let charactersPerToken = 3

    /// Returns whether `recipient` may receive `allegato` without asking the user.
    static func allows(_ allegato: Allegato, to recipient: Recipient) -> Bool {
        switch recipient {
        case .claude: true
        case .onDevice: allegato.text != nil
        case .otherProvider: false
        }
    }

    /// The tokens `text` is estimated at, with no tokenizer: one every ``charactersPerToken`` characters, rounded up.
    static func estimatedTokens(of text: String) -> Int {
        (text.count + charactersPerToken - 1) / charactersPerToken
    }

    /// The most tokens of Allegati an endpoint with `contextLength` takes: half of it, the rest to instructions,
    /// question and answer; ``fixedCap`` when the endpoint tells no context.
    static func cap(contextLength: Int?) -> Int {
        contextLength.map { $0 / 2 } ?? fixedCap
    }

    /// What may go to `endpoint` of `attachments`.
    ///
    /// - Parameters:
    ///   - contextLength: The context of the endpoint's model, as its server tells it; `nil` when it tells none.
    ///   - confirmed: The Allegati the user already confirmed for `endpoint`.
    static func verdict(for attachments: [Allegato], to endpoint: OpenAICompatibleEndpoint, contextLength: Int?,
                        confirmed: Set<Allegato>) -> Verdict {
        if let withoutText = attachments.first(where: { $0.text == nil }) { return .onlyClaude(withoutText) }
        let tokens = attachments.compactMap(\.text).map(estimatedTokens(of:)).reduce(0, +)
        let cap = cap(contextLength: contextLength)
        if tokens > cap { return .overCap(tokens: tokens, cap: cap) }
        let unconfirmed = endpoint.isOnMac ? [] : attachments.filter { !confirmed.contains($0) }
        return unconfirmed.isEmpty ? .allowed : .needsConfirmation(unconfirmed)
    }

    /// What an endpoint reads of a Domanda: `question`, then each Allegato's text under its name.
    static func prompt(_ question: String, attachments: [Allegato]) -> String {
        ([question] + attachments.map { "--- \($0.name) ---\n\($0.text ?? "")" }).joined(separator: "\n\n")
    }
}
