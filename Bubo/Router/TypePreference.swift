/// What the user chose with "Usa sempre per «Tipo»": who answers the Domande of a Tipo instead of its default
/// (spec 10, Override sul turno).
nonisolated enum TypePreference: Codable, Equatable, Sendable {
    /// A Claude model at an effort.
    case claude(Scala.Step)
    /// The OpenAI-compatible endpoint with this id, with the model the user set for it.
    case endpoint(id: String)
    /// A model of the user's Copilot plan, by its id and name, at its own default effort (ADR 0011).
    case copilot(id: String, name: String)
}
