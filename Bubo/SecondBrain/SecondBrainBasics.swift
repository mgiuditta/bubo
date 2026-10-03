import Foundation

/// The base of the Secondo cervello that every turn gets in its system prompt: the Profilo and the Regole.
nonisolated enum SecondBrainBasics {
    /// The notes that come into every turn, relative to the Secondo cervello.
    static let notes = ["Bubo/Profilo.md", "Bubo/Regole.md"]

    /// The most characters of the notes that come in: about 2.000 tokens.
    static let characterLimit = 8_000

    /// The system prompt's text for the Secondo cervello at `root`: the notes that are there, up to
    /// ``characterLimit`` with a note to `cerca` for the rest, after what to save with `ricorda`.
    ///
    /// - Returns: `nil` when neither note is there, so nothing comes in.
    static func prompt(in root: URL, savesOnItsOwn: Bool) -> String? {
        let found = notes.compactMap { path in
            read(root.appending(path: path)).map { "## \(path)\n\n\($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
        }
        guard !found.isEmpty else { return nil }
        var body = found.joined(separator: "\n\n")
        if body.count > characterLimit {
            body = String(body.prefix(characterLimit)) + "\n\n[…] Il resto non entra qui: usa cerca per il resto."
        }
        let saving = savesOnItsOwn
            ? "Salva da solo con ricorda i fatti durevoli sull'utente (preferenze, persone, progetti, decisioni), "
                + "seguendo Bubo/Regole.md; aggiorna Bubo/Profilo.md quando cambia ciò che sai di lui."
            : "Salva con ricorda solo quando l'utente te lo chiede."
        return """
            Il Secondo cervello dell'utente, la sua cartella di note, ha due note che Bubo ti dà a ogni turno: \
            Bubo/Profilo.md (chi è l'utente) e Bubo/Regole.md (cosa salvare, dove, come). Le altre note cercale con \
            cerca. \(saving)

            \(body)
            """
    }

    /// The text of the note at `file`, read only up to what can come in; `nil` when it is not there.
    private static func read(_ file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        // A character takes at most 4 bytes in UTF-8.
        guard let data = try? handle.read(upToCount: characterLimit * 4) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
