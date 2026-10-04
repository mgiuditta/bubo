import Foundation

/// The speakers of a Riunione's note that the user can name, and the note rewritten with their names (#574).
///
/// The note is rewritten in place: its file keeps its name, so the links to it stay valid.
nonisolated enum MeetingSpeakers {
    /// The speakers of `note` that can take a name, in the order they first speak: «Parlante 1», «Parlante 2»…
    /// and those already named, such as `[[Giulia]]`.
    static func named(in note: String) -> [String] {
        speakers(in: split(note).body)
    }

    /// The speakers that can take a name in the lines of `body`, in the order they first speak.
    private static func speakers(in body: some StringProtocol) -> [String] {
        var speakers: [String] = []
        for match in String(body).matches(of: heading) {
            let speaker = String(match.output.1)
            if isRenamable(speaker), !speakers.contains(speaker) { speakers.append(speaker) }
        }
        return speakers
    }

    /// `note` with `speaker` called `[[name]]` in the summary and in the trascrizione, and `[[name]]` among the
    /// `partecipanti` once; unchanged when `name` is empty.
    ///
    /// - Parameters:
    ///   - speaker: A speaker from ``named(in:)``, such as «Parlante 1» or `[[Giulia]]`.
    ///   - name: The person's name, without brackets.
    static func renaming(_ speaker: String, to name: String, in note: String) -> String {
        let link = "[[\(cleaned(name))]]"
        guard isRenamable(speaker), link != "[[]]", link != speaker else { return note }
        let (properties, body) = split(note)
        let renamed = String(body).replacing(/\[\[[^\[\]\n]+\]\]|\bParlante \d+/) { match in
            match.output == speaker ? link : String(match.output)
        }
        let remaining = speakers(in: renamed)
        var participants = participants(in: properties).filter { $0 != speaker || remaining.contains($0) }
        if !participants.contains(link) { participants.append(link) }
        let line = "partecipanti: [\(participants.map(SummaryProperties.quoted).joined(separator: ", "))]"
        let rewritten = properties.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("partecipanti:") ? line : String($0) }
            .joined(separator: "\n")
        return rewritten + renamed
    }

    /// Renames `speaker` to `name` in the note at `file`, which keeps its name.
    static func rename(_ speaker: String, to name: String, inNoteAt file: URL) throws {
        let note = try String(contentsOf: file, encoding: .utf8)
        let renamed = renaming(speaker, to: name, in: note)
        guard renamed != note else { return }
        try renamed.write(to: file, atomically: true, encoding: .utf8)
    }

    /// The speaker of a line of the trascrizione, as in `**[0:01:23] Parlante 1:**`.
    private static var heading: Regex<(Substring, Substring)> { /(?m)^\*\*\[[^\]\n]*\] (.+?):\*\*/ }

    /// Whether `speaker` is one Bubo numbered or the user named: «Io» and «Altri» stay as they are.
    private static func isRenamable(_ speaker: String) -> Bool {
        speaker.wholeMatch(of: /Parlante \d+/) != nil || speaker.wholeMatch(of: /\[\[[^\[\]]+\]\]/) != nil
    }

    /// `name` on one line, without the characters that would break a link in Obsidian.
    private static func cleaned(_ name: String) -> String {
        let forbidden = Set("[]|#^\"\\")
        return name.split(whereSeparator: \.isNewline).joined(separator: " ")
            .filter { !forbidden.contains($0) }
            .trimmingCharacters(in: .whitespaces)
    }

    /// The properties of `note`, with their closing `---` line, and the rest.
    private static func split(_ note: String) -> (properties: String, body: Substring) {
        guard note.hasPrefix("---\n"), let end = note.range(of: "\n---\n", range: note.index(note.startIndex, offsetBy: 3)..<note.endIndex)
        else { return ("", note[...]) }
        return (String(note[..<end.upperBound]), note[end.upperBound...])
    }

    /// The names in the `partecipanti` property of `properties`.
    private static func participants(in properties: String) -> [String] {
        guard let line = properties.split(separator: "\n").first(where: { $0.hasPrefix("partecipanti:") }) else { return [] }
        return line.matches(of: /"((?:[^"\\]|\\.)*)"/).map {
            String($0.output.1).replacing("\\\"", with: "\"").replacing("\\\\", with: "\\")
        }
    }
}
