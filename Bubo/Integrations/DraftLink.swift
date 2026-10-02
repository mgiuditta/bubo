import Foundation

/// A `bubo://draft` link, an entry from outside Bubo: anyone can write one, a web page too, so it can only ever make a
/// Bozza, never start a Sessione (spec 16).
///
/// `bubo://draft?project=<absolute path>&title=…&text=…` makes a Bozza written by hand;
/// `bubo://draft?project=<absolute path>&source=github&id=<number>[&title=…]` a Bozza from a GitHub issue, whose text is
/// read with `gh` at Avvia, so the link's `text` is not kept. Unknown parameters are ignored; a known one given twice,
/// an unknown source or a path that is not absolute make no Bozza at all.
nonisolated struct DraftLink: Equatable, Sendable {
    /// The Progetto's folder, as the link names it: whether it exists is checked when the Bozza is made.
    var project: URL
    var title: String
    var text: String
    var issue: IssueLink?

    /// The longest title kept, in characters; the rest is cut.
    static let maximumTitleLength = 200
    /// The longest text kept, in characters; the rest is cut.
    static let maximumTextLength = 4_000

    /// The Bozza `url` asks for; `nil` when it is not a valid `bubo://draft` link.
    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "bubo", url.host()?.lowercased() == "draft",
              ["", "/"].contains(url.path(percentEncoded: false)),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        let known = ["project", "title", "text", "source", "id"]
        var values: [String: String] = [:]
        for item in items where known.contains(item.name) {
            // The same parameter twice: which one counts is anybody's guess.
            guard values[item.name] == nil else { return nil }
            values[item.name] = item.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        guard let path = values["project"], path.hasPrefix("/") else { return nil }
        project = URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
        let title = values["title"].map { Self.line(String($0.prefix(Self.maximumTitleLength))) } ?? ""
        switch values["source"] {
        case nil:
            guard !title.isEmpty else { return nil }
            self.title = title
            text = String((values["text"] ?? "").prefix(Self.maximumTextLength))
            issue = nil
        case "github":
            guard let id = values["id"], let number = Int(id), number > 0, String(number) == id else { return nil }
            self.title = title.isEmpty ? "#\(number)" : title
            text = ""
            issue = .github(number)
        default:
            return nil
        }
    }

    /// `text` on one line: its line breaks and other control characters become spaces.
    private static func line(_ text: String) -> String {
        String(text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) })
    }
}
