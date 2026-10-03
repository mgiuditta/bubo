import Foundation

/// A document imported in the Secondo cervello, as a note: properties for Obsidian, a short summary, then its text.
///
/// The section titles and the properties are part of the note's format, fixed in Italian.
nonisolated struct DocumentNote: Equatable, Sendable {
    var title: String
    /// The imported file's name, as `Contratto.pdf`.
    var source: String
    var document: DocumentText
    /// The SHA-256 of the imported file, in hexadecimal: the same file is never imported twice.
    var fingerprint: String
    /// The summary; `nil` when no model on the Mac could write it.
    var summary: String?

    /// What the model is asked for the summary.
    static let instructions = """
        Riassumi questo documento in al più 3 frasi, nella sua lingua. Rispondi solo con il riassunto, \
        senza introduzione né titolo. Non riportare chiavi, token, password né altri segreti.
        """

    /// The property that holds the fingerprint, read back to find a document already imported.
    static let fingerprintKey = "impronta"

    /// The whole note, imported on `day`, as `AAAA-MM-GG`.
    func markdown(importedOn day: String) -> String {
        var properties = [
            "---",
            "titolo: \(SummaryProperties.quoted(title))",
            "fonte: \(SummaryProperties.quoted(source))",
            "tipo: \(document.kind.rawValue)",
            "importata: \(day)",
        ]
        if let pages = document.pageCount { properties.append("pagine: \(pages)") }
        if document.isRecognized { properties.append("ocr: true") }
        properties += ["\(Self.fingerprintKey): \(SummaryProperties.quoted(fingerprint))", "---"]
        let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summarySection = summary.isEmpty ? "Non scritto: nessun modello era disponibile." : summary
        return properties.joined(separator: "\n") + "\n\n## Riassunto\n\n" + summarySection
            + "\n\n## Testo\n\n" + document.text + "\n"
    }

    /// Whether the note `text` is the one of the file whose SHA-256 is `fingerprint`.
    static func note(_ text: String, isOfFileWithFingerprint fingerprint: String) -> Bool {
        let line = "\(fingerprintKey): \(SummaryProperties.quoted(fingerprint))"
        // Only the properties, between the first two `---` lines.
        let properties = text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().prefix { $0 != "---" }
        return text.hasPrefix("---") && properties.contains { $0.trimmingCharacters(in: .whitespaces) == line }
    }
}
