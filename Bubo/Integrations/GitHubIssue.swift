import Foundation

/// An open issue in the ⌘I sheet, as `gh issue list --json number,title,labels,updatedAt,url` gives it.
nonisolated struct GitHubIssue: Decodable, Identifiable, Equatable, Sendable {
    /// A label of an issue, by name.
    struct Label: Decodable, Equatable, Sendable {
        var name: String
    }

    var number: Int
    var title: String
    var labels: [Label]
    var updatedAt: Date
    var url: URL

    var id: Int { number }

    /// The fields `gh issue list` is asked for.
    static let fields = "number,title,labels,updatedAt,url"
}
