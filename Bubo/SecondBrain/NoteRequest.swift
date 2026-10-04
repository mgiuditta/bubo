import Foundation

/// What the `ricorda` tool asks Bubo to write in the Secondo cervello.
nonisolated struct NoteRequest: Equatable, Sendable {
    /// How the note is written.
    enum Mode: String, Sendable {
        /// A new note in `Bubo/Note/`, named after its title.
        case new = "nuova"
        /// The text goes at the end of an existing note, or of a new one under `Bubo/`.
        case append = "aggiungi"
        /// The text replaces the whole note: only a note under `Bubo/`, or another the user confirmed.
        case replace = "riscrivi"
    }

    var mode = Mode.new
    /// The new note's title, which becomes its file name.
    var title: String?
    /// The note to add to or rewrite, as a path relative to the Secondo cervello, such as `Bubo/Profilo.md`.
    var note: String?
    /// What to write, in Markdown.
    var text: String
    /// Whether the user confirmed rewriting a note of theirs, outside `Bubo/`.
    var isConfirmed = false
}
