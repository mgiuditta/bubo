import Foundation

/// A prompt that calls a skill with `/name` at its start, and what Bubo sends instead of it to a model that does not
/// run skills on its own (#689).
nonisolated struct SkillInvocation: Sendable, Hashable {
    /// The skill called.
    let skill: Skill
    /// What follows `/name`, trimmed; empty when the prompt is the name alone.
    let request: String

    /// Creates the invocation of `skill` for `request`.
    init(skill: Skill, request: String) {
        self.skill = skill
        self.request = request
    }

    /// Reads `/name request` at the start of `text`, `name` being one of `skills`; `nil` when `text` does not start
    /// with `/`, or the name is none of them: an unknown `/x` is plain text.
    init?(parsing text: String, among skills: [Skill]) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("/") else { return nil }
        let call = text.dropFirst()
        let name = call.prefix { !$0.isWhitespace }
        guard !name.isEmpty, let skill = skills.first(where: { $0.name == name }) else { return nil }
        self.skill = skill
        request = call.dropFirst(name.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text a model reads: the skill's instructions in a `<skill>` block, then ``request``.
    ///
    /// - Parameter showingFolder: Whether to say where the skill's folder is, for Claude, which can read the files
    ///   next to its `SKILL.md`; the other models get the instructions alone.
    func expanded(showingFolder: Bool = false) -> String {
        var parts = ["<skill name=\"\(skill.name)\">\n\(skill.body)\n</skill>"]
        if showingFolder, let directory = skill.directory {
            parts.append(String(localized: "I file della skill sono in \(directory.path(percentEncoded: false)): puoi leggerli quando le istruzioni li citano.",
                                comment: "Sent to Claude after a skill's instructions: the folder of its files, which Claude may read"))
        }
        if !request.isEmpty { parts.append(request) }
        return parts.joined(separator: "\n\n")
    }
}
