import Foundation

/// How Fondi brings a Sessione into the Progetto's checkout: squash by default, a merge commit when the Progetto
/// prefers it.
nonisolated enum MergeStrategy: String, Codable, CaseIterable, Sendable {
    /// One new commit with every change of the Sessione.
    case squash
    /// A commit with two parents: the checkout's branch and the Sessione's work.
    case mergeCommit

    /// The strategy's name in the revisione.
    var title: LocalizedStringResource {
        switch self {
        case .squash: "Squash"
        case .mergeCommit: "Merge commit"
        }
    }

    /// The `UserDefaults` key of the strategy each Progetto prefers, by the path of its folder.
    static let defaultsKey = "mergeStrategies"

    /// The strategy `project` prefers in `defaults`: squash unless the user chose otherwise.
    static func preferred(for project: URL, in defaults: UserDefaults = .standard) -> MergeStrategy {
        let saved = defaults.dictionary(forKey: defaultsKey)?[project.standardizedFileURL.path] as? String
        return saved.flatMap(MergeStrategy.init(rawValue:)) ?? .squash
    }

    /// Makes this the strategy `project` prefers in `defaults`.
    func makePreferred(for project: URL, in defaults: UserDefaults = .standard) {
        var saved = defaults.dictionary(forKey: Self.defaultsKey) ?? [:]
        saved[project.standardizedFileURL.path] = rawValue
        defaults.set(saved, forKey: Self.defaultsKey)
    }
}
