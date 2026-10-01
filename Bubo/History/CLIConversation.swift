import Foundation

/// A conversation of the Cronologia CLI, as the SDK lists it: Bubo reads it, and resumes it only as a fork.
nonisolated struct CLIConversation: Decodable, Identifiable, Equatable, Sendable {
    /// One message of the conversation: only the text of who spoke.
    struct Message: Decodable, Equatable, Sendable {
        /// The message's id in the conversation, if the bridge sent it.
        let id: String?
        /// Whether the user wrote it; otherwise Claude did.
        let isFromUser: Bool
        let text: String
        /// When it was written; known only for a conversation copied in Bubo's database.
        let date: Date?

        private enum CodingKeys: String, CodingKey {
            case id, role, text, date
        }

        init(id: String? = nil, isFromUser: Bool, text: String, date: Date? = nil) {
            self.id = id
            self.isFromUser = isFromUser
            self.text = text
            self.date = date
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            isFromUser = try container.decode(String.self, forKey: .role) == "user"
            text = try container.decode(String.self, forKey: .text)
            date = try container.decodeIfPresent(Double.self, forKey: .date).map { Date(timeIntervalSince1970: $0 / 1000) }
        }
    }

    /// The id of the agent's conversation in `claude`.
    let id: String
    /// The title the CLI shows: the one given with `/rename`, its summary or the first prompt.
    let title: String
    /// The folder it ran in, if the CLI recorded it.
    let folder: URL?
    /// The git branch at its end.
    let branch: String?
    let lastModified: Date

    private enum CodingKeys: String, CodingKey {
        case id, title, cwd, branch, lastModified
    }

    init(id: String, title: String, folder: URL?, branch: String?, lastModified: Date) {
        self.id = id
        self.title = title
        self.folder = folder
        self.branch = branch
        self.lastModified = lastModified
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        folder = try container.decodeIfPresent(String.self, forKey: .cwd)
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        lastModified = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .lastModified) / 1000)
    }

    /// Whether `text` appears in its title, its folder or its branch.
    func matches(_ text: String) -> Bool {
        [title, folder?.path, branch].contains { $0?.localizedStandardContains(text) == true }
    }
}
