import Foundation

/// Writes the minimal file of Nuovo agente: `name`, `description` and an empty body for the user to fill in the
/// editor (spec 19).
///
/// It is the only file Bubo writes in an `agents/` folder, and only when the user clicks: nothing else calls
/// ``write(name:description:)``.
nonisolated struct AgentFileWriter: Sendable {
    /// Why Nuovo agente cannot write the file.
    enum Refusal: Error, Equatable, Sendable {
        case missingName
        case missingDescription
        /// The name is not lowercase letters, digits and hyphens, as the documentation of Claude Code asks: no `:`,
        /// which `claude` refuses, and no leading `-`.
        case invalidName
        /// A file of the same source already declares the name.
        case nameTaken(URL)
        /// The folder already has a file with that name, declaring another agent.
        case fileExists(URL)

        /// The reason, next to the disabled button.
        var message: LocalizedStringResource {
            switch self {
            case .missingName: "Scrivi un nome."
            case .missingDescription: "Scrivi una descrizione: dice a Claude quando usare l'agente."
            case .invalidName: "Usa solo lettere minuscole, cifre e trattini, senza iniziare con un trattino."
            case let .nameTaken(file): "Un agente con questo nome c'è già: \(file.path)"
            case let .fileExists(file): "Il file \(file.path) c'è già."
            }
        }
    }

    /// The `agents/` folder the file goes in: the Progetto's `.claude/agents` or the user's `~/.claude/agents`.
    let folder: URL
    /// The agents already declared in the source of ``folder``, its subfolders and nested folders included.
    let existing: [AgentFile]

    /// The line of the empty body, where the editor opens.
    static let bodyLine = 5

    /// The file a new agent named `name` goes in.
    func file(named name: String) -> URL {
        folder.appending(path: "\(name.trimmingCharacters(in: .whitespaces)).md")
    }

    /// Why the agent `name` described by `description` cannot be written; `nil` when it can.
    ///
    /// Reads the disk to see whether the file exists, never writes.
    func refusal(name: String, description: String) -> Refusal? {
        let name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return .missingName }
        if name.hasPrefix("-") || !name.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }) {
            return .invalidName
        }
        if let taken = existing.first(where: { $0.name == name }) { return .nameTaken(taken.file) }
        if FileManager.default.fileExists(atPath: file(named: name).path) { return .fileExists(file(named: name)) }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingDescription }
        return nil
    }

    /// Writes the file of the agent `name` described by `description`, creating the folder, and returns it.
    ///
    /// - Throws: The ``Refusal`` when the name cannot be used, or the error of the disk; never overwrites a file.
    func write(name: String, description: String) throws -> URL {
        if let refusal = refusal(name: name, description: description) { throw refusal }
        let file = file(named: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(Self.content(name: name, description: description).utf8).write(to: file, options: .withoutOverwriting)
        return file
    }

    /// The text of the file: the frontmatter, with the description on one quoted line, and an empty body.
    static func content(name: String, description: String) -> String {
        let line = description.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        let quoted = line.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
        return "---\nname: \(name.trimmingCharacters(in: .whitespaces))\ndescription: \"\(quoted)\"\n---\n\n"
    }
}
