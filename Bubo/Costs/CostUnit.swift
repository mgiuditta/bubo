import Foundation

/// The unit of a figure in the CostLedger; figures of different units are never added together.
nonisolated enum CostUnit: String, Codable, CaseIterable, Sendable {
    /// Dollars paid per use: Claude with the API key, or another provider on the user's key.
    case spesa
    /// Dollars not paid: what the subscription's work would cost per use.
    case valoreListino
    /// The Cronologia CLI at list prices: its transcript does not say whether the subscription or the API key paid,
    /// so it is never Spesa.
    case rigaDiComando
    /// Nothing to pay: Ollama, LM Studio and Apple FM on the Mac, with their tokens.
    case gratis
}
