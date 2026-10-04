/// A folder of the Secondo cervello and the fragments of its notes in the Indice.
nonisolated struct FolderLoad: Equatable, Sendable {
    /// Relative to the Secondo cervello: a folder directly inside it.
    var relativePath: String
    /// The fragments of the notes at or under the folder.
    var fragmentCount: Int
}

/// How full the Indice is.
nonisolated struct FragmentLoad: Equatable, Sendable {
    /// The fragments of every source: memory, Secondo cervello and conversations.
    var fragmentCount: Int
    /// The fragments beyond which searches slow down.
    var limit: Int
    /// The largest folders of the Secondo cervello, most fragments first.
    var largestFolders: [FolderLoad]

    /// Whether the Indice holds more fragments than ``limit``.
    var exceedsLimit: Bool { fragmentCount > limit }
}
