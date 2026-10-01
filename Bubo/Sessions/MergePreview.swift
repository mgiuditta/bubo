/// What Fondi would do now, worked out without touching the Progetto's checkout.
nonisolated struct MergePreview: Equatable, Sendable {
    /// The branch of the checkout the Sessione would go into.
    var branch: String
    /// The files that would conflict, relative to the repo.
    var conflicts: [String]
    /// The files the merge would change that have unsaved changes in the checkout.
    var dirtyFiles: [String]
    /// Whether the merge would change no file: the branch already has the Sessione's work.
    var isEmpty: Bool

    /// Why Fondi cannot go ahead; `nil` when it can.
    var obstacle: MergeError? {
        if !conflicts.isEmpty { return .conflicts(conflicts) }
        if !dirtyFiles.isEmpty { return .dirtyCheckout(dirtyFiles) }
        if isEmpty { return .nothingToMerge }
        return nil
    }
}
