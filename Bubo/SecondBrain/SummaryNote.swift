import Foundation

/// The Riassunto di Sessione note, as Bubo last wrote it: kept on the Sessione, to update the same note.
nonisolated struct SummaryNote: Codable, Equatable, Sendable {
    /// The note's path relative to the Secondo cervello, which can move: `Bubo/Sessioni/AAAA-MM-GG Titolo.md`.
    var relativePath: String
    /// The SHA-256 of the bytes Bubo last wrote, in hexadecimal.
    var hash: String
    /// The day the note was first written, `AAAA-MM-GG`.
    var createdOn: String
    /// Whether the user changed the note by hand: from then on Bubo only adds `## Aggiornamento` sections, for good.
    var isEditedByHand = false
}
