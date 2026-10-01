/// The branch of a Progetto's checkout brought into a Sessione's worktree, with the conflicts its agent resolves
/// there and what putting the worktree back needs.
nonisolated struct ConflictResolution: Codable, Equatable, Sendable {
    /// The checkout's branch, such as `main`.
    var branch: String
    /// The commit of that branch brought in: the revisione's base once the conflicts are resolved.
    var incoming: String
    /// The commit the Sessione's branch was on before.
    var previous: String
    /// A commit with every file of the worktree before, also what was not committed, on top of `previous`.
    var snapshot: String
    /// The files in conflict, relative to the repo.
    var conflicts: [String]
}
