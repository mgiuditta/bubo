import Foundation

/// Notes found by one search that look like the same thing, as the standup of two different days: when the
/// request does not say which one, the model asks once instead of mixing them.
nonisolated enum SimilarNotes {
    /// Returns the instruction asking for one clarifying question when some of `notes` share a title, the date in
    /// front of their names aside; `nil` when no two do.
    ///
    /// - Parameter notes: The notes found, as their citations name them: paths without `.md`, best first.
    static func clarification(among notes: [String]) -> String? {
        guard let options = firstGroup(among: notes) else { return nil }
        let listed = options.map { "[[\($0)]]" }.joined(separator: ", ")
        return "Le note \(listed) sembrano la stessa cosa in momenti diversi. Se la richiesta non dice quale intende, "
            + "non mescolarle: fai all'utente una sola domanda breve con queste opzioni, per esempio \"Lo standup del 2 "
            + "o del 3 ottobre?\", e aspetta la risposta. Se la tua risposta precedente era già una domanda di "
            + "chiarimento, non farne un'altra: usa la nota più recente e dillo."
    }

    /// The first notes of `notes` sharing a title, in their order; `nil` when every title is different.
    /// Notes named only by a date are left out.
    static func firstGroup(among notes: [String]) -> [String]? {
        var seen: Set<String> = []
        // A note named only by its date, as a daily note, has no title to share.
        let distinct = notes.filter { seen.insert($0).inserted && !title(of: $0).isEmpty }
        let groups = Dictionary(grouping: distinct, by: title(of:))
        guard let group = distinct.lazy.compactMap({ groups[title(of: $0)] }).first(where: { $0.count > 1 }) else {
            return nil
        }
        return group
    }

    /// The title of `note`: its name without the folder and the leading `AAAA-MM-GG` date, in lowercase.
    static func title(of note: String) -> String {
        let name = note.split(separator: "/").last.map(String.init) ?? note
        let undated = name.replacing(/^\d{4}-\d{2}-\d{2}[ _-]*/, with: "")
        return undated.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
