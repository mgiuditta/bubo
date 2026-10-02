import Foundation

/// The pull request Apri PR opened for a Sessione on GitHub (spec 16).
nonisolated struct PullRequestLink: Codable, Equatable, Sendable {
    var number: Int
    var url: URL
    /// The branch the pull request goes into.
    var base: String

    /// The pull request at `url`, as `gh pr create` prints it, such as `https://github.com/o/r/pull/7`, going into
    /// `base`; `nil` for any other text.
    init?(url text: String, base: String) {
        guard let line = text.split(whereSeparator: \.isNewline).last(where: { $0.contains("/pull/") }),
              let url = URL(string: line.trimmingCharacters(in: .whitespaces)),
              url.pathComponents.dropLast().last == "pull", let number = Int(url.lastPathComponent)
        else { return nil }
        self.number = number
        self.url = url
        self.base = base
    }

    /// The reference on the card and in the Sessione: `PR #7`.
    var label: String { "PR #\(number)" }
}
