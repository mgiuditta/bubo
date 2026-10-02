/// Where a git source of a Marketplace entry points: the commit it is pinned to, the branch or tag it follows.
nonisolated struct PluginRevision: Sendable, Equatable {
    /// `sha`: the full commit; `nil` when the entry follows `ref`.
    var sha: String?
    /// `ref`: a branch or a tag; `nil` for the default branch.
    var ref: String?

    /// Creates a revision pinned to `sha`, following `ref`.
    init(sha: String? = nil, ref: String? = nil) {
        self.sha = sha
        self.ref = ref
    }

    /// Reads `sha` and `ref` of the `source` object of a Marketplace entry; empty for a relative path.
    init(json: Any?) {
        let object = json as? [String: Any]
        self.init(sha: (object?["sha"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                  ref: (object?["ref"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }
}
