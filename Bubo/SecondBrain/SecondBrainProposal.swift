import Foundation

/// The settings of the Secondo cervello the model proposes at the end of the setup conversation, in a block
/// ` ```secondo-cervello ` holding JSON. Nothing is applied until the user confirms it.
nonisolated struct SecondBrainProposal: Decodable, Equatable, Sendable {
    /// What to do with ``folder``.
    enum Action: String, Decodable, Sendable {
        /// Use a folder of notes the user already has.
        case use = "usa"
        /// Create a new folder, with the minimal standard structure.
        case create = "crea"
    }

    var action: Action
    /// The folder's path; `~` stands for the home folder.
    var path: String
    /// Folders left out of the Indice, relative to the folder.
    var excludedFolders: [String] = []
    /// Folders whose notes `cerca` puts first, relative to the folder.
    var priorityFolders: [String] = []
    /// The people the user often works with.
    var people: [String] = []
    /// The projects the user follows.
    var projects: [String] = []

    /// The language of the block and the info string of its fence.
    static let fence = "secondo-cervello"

    /// The folders a new Secondo cervello starts with, besides `Bubo/`, which Bubo creates when it first writes.
    static let standardFolders = ["Note", "Progetti", "Persone"]

    private enum CodingKeys: String, CodingKey {
        case action = "azione", path = "cartella", excludedFolders = "escluse", priorityFolders = "prioritarie"
        case people = "persone", projects = "progetti"
    }

    init(action: Action, path: String, excludedFolders: [String] = [], priorityFolders: [String] = [],
         people: [String] = [], projects: [String] = []) {
        self.action = action
        self.path = path
        self.excludedFolders = excludedFolders
        self.priorityFolders = priorityFolders
        self.people = people
        self.projects = projects
    }

    /// Decodes a proposal, with only `azione` and `cartella` required.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(Action.self, forKey: .action)
        path = try container.decode(String.self, forKey: .path)
        excludedFolders = try container.decodeIfPresent([String].self, forKey: .excludedFolders) ?? []
        priorityFolders = try container.decodeIfPresent([String].self, forKey: .priorityFolders) ?? []
        people = try container.decodeIfPresent([String].self, forKey: .people) ?? []
        projects = try container.decodeIfPresent([String].self, forKey: .projects) ?? []
    }

    /// The folder, with `~` expanded.
    var folder: URL {
        URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    }

    /// The last proposal in `answer`, or `nil` when it holds none or it cannot be read.
    init?(in answer: String) {
        guard let block = Self.block(in: answer),
              let proposal = try? JSONDecoder().decode(Self.self, from: Data(answer[block.content].utf8)),
              !proposal.path.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        self = proposal
    }

    /// `answer` without its proposal block, as the conversation shows it; a block still streaming, not yet closed, goes
    /// too.
    static func prose(of answer: String) -> String {
        guard let opening = answer.range(of: "```" + fence, options: .backwards) else { return answer }
        let end = answer.range(of: "```", range: opening.upperBound..<answer.endIndex)?.upperBound ?? answer.endIndex
        var prose = answer
        prose.removeSubrange(opening.lowerBound..<end)
        return prose.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The range of the last proposal block in `answer`, fences included, and of its content.
    private static func block(in answer: String) -> (whole: Range<String.Index>, content: Range<String.Index>)? {
        guard let opening = answer.range(of: "```" + fence, options: .backwards),
              let closing = answer.range(of: "```", range: opening.upperBound..<answer.endIndex)
        else { return nil }
        return (opening.lowerBound..<closing.upperBound, opening.upperBound..<closing.lowerBound)
    }
}
