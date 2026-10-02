/// A text, file or screenshot that comes with a Richiesta; today its name and its text, which #98 widens.
nonisolated struct Allegato: Hashable, Sendable {
    /// The file name, without its path: all a classifier may see of it.
    let name: String
    /// The content the answering model reads.
    let text: String
}
