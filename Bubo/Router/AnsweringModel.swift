/// The model that actually answered a turn and its effective effort, as the bridge read them from the SDK.
nonisolated struct AnsweringModel: Equatable, Sendable {
    /// The model's id, such as `claude-haiku-4-5-20251001`.
    let model: String
    /// The effort after any silent downgrade by the SDK; `nil` for a model without effort, such as Haiku.
    let effort: Effort?

    /// The model as people call it, such as "Haiku 4.5"; the id itself when it does not read as a Claude model's.
    var name: String {
        var parts = model.prefix { $0 != "[" }.split(separator: "-").map(String.init)
        guard parts.first == "claude" else { return model }
        parts.removeFirst()
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        guard let family = parts.first, family.allSatisfy(\.isLetter), parts.count > 1,
              parts.dropFirst().allSatisfy({ $0.allSatisfy(\.isNumber) })
        else { return model }
        return "\(family.capitalized) \(parts.dropFirst().joined(separator: "."))"
    }
}
