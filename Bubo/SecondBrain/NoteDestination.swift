import Foundation

/// Where a cited note opens: in Obsidian, when the Secondo cervello is its vault and Obsidian is on the Mac, otherwise
/// in Quick Look inside Bubo.
nonisolated enum NoteDestination: Equatable, Sendable {
    /// Obsidian, through its `obsidian://open` link to the note's file.
    case obsidian(URL)
    /// Quick Look, on the note's file.
    case quickLook(URL)

    /// Creates the destination of `file`, a note of a Secondo cervello that `isObsidianVault` tells apart, with
    /// Obsidian on the Mac or not.
    init(file: URL, isObsidianVault: Bool, hasObsidian: Bool) {
        guard isObsidianVault, hasObsidian, let link = Self.obsidianLink(to: file) else {
            self = .quickLook(file)
            return
        }
        self = .obsidian(link)
    }

    /// The link that opens `file` in Obsidian, which finds the vault on its own from the absolute path.
    static func obsidianLink(to file: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: file.path)]
        return components.url
    }
}
