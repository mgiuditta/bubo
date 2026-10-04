import DeliveryKit
import Foundation

/// The HTML page of a ``BuboFileSummary``, in Bubo's dark palette (`docs/design-system.md`).
///
/// A warning is red and also starts with a warning sign and says what is wrong in words. Every name comes from a
/// file anyone can write, so it is escaped.
nonisolated struct PreviewPage {
    /// What the page shows.
    let summary: BuboFileSummary

    /// One line of the page: a label and its value, which is HTML already.
    private struct Row {
        let label: String
        let value: String
    }

    /// The whole page.
    var html: String {
        let title: String
        let rows: [Row]
        let note: String
        switch summary {
        case let .consegna(sender, recipient, size):
            title = String(localized: "Consegna Bubo, cifrata")
            rows = [
                Row(label: String(localized: "Da"), value: Self.text(of: sender)),
                Row(label: String(localized: "Per"), value: Self.text(of: recipient)),
                Row(label: String(localized: "Dimensioni"),
                    value: Self.escaped(Int64(clamping: size).formatted(.byteCount(style: .file)))),
            ]
            note = String(localized: "Aprila in Bubo per leggerla.")
        case let .biglietto(person, machine, key):
            title = String(localized: "Biglietto Bubo")
            rows = [
                Row(label: String(localized: "Di"), value: Self.escaped("\(person) · \(machine)")),
                Row(label: String(localized: "Chiave"), value: "<code>\(Self.grouped(key))</code>"),
            ]
            note = String(localized: "Aprilo in Bubo e confronta il codice a voce con l'altra persona.")
        }
        let list = rows.map { "<dt>\(Self.escaped($0.label))</dt><dd>\($0.value)</dd>" }.joined()
        let language = Bundle.main.preferredLocalizations.first ?? "it"
        return """
            <!doctype html><html lang="\(language)"><head><meta charset="utf-8"><style>\(Self.style)</style></head>
            <body><h1>\(Self.escaped(title))</h1><dl>\(list)</dl><p>\(Self.escaped(note))</p></body></html>
            """
    }

    private static func text(of sender: BuboFileSummary.Sender) -> String {
        switch sender {
        case let .known(person, machine): escaped("\(person) · \(machine)")
        case .unknown: warning(String(localized: "mittente sconosciuto"))
        }
    }

    private static func text(of recipient: BuboFileSummary.Recipient) -> String {
        switch recipient {
        case .thisMachine: escaped(String(localized: "questa Macchina"))
        case let .otherMachine(machine?): warning(String(localized: "\(machine), non questa Macchina"))
        case .otherMachine(nil): warning(String(localized: "un'altra Macchina"))
        case .undetermined: escaped(String(localized: "da verificare in Bubo"))
        }
    }

    /// `text` in red, after a warning sign that VoiceOver reads as a word.
    private static func warning(_ text: String) -> String {
        let sign = escaped(String(localized: "Attenzione"))
        return "<span class=\"warning\"><span role=\"img\" aria-label=\"\(sign)\">⚠︎</span> \(escaped(text))</span>"
    }

    /// The 16 hexadecimal digits of `key`, in groups of 4 to read them out.
    private static func grouped(_ key: KeyID) -> String {
        let digits = Array(key.description)
        return stride(from: 0, to: digits.count, by: 4).map { String(digits[$0..<min($0 + 4, digits.count)]) }
            .joined(separator: " ")
    }

    /// `text` with the characters HTML gives a meaning to replaced.
    static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    /// The palette's `ink`, `textPrimary`, `textSecondary` and `danger`.
    private static let style = """
        :root{color-scheme:dark}
        body{margin:0;padding:24px 28px;background:#0A0B0D;color:#ECEEF1;font:13px/1.45 -apple-system,sans-serif}
        h1{margin:0 0 14px;font-size:17px;font-weight:600}
        dl{display:grid;grid-template-columns:max-content 1fr;gap:6px 16px;margin:0}
        dt{color:#8E939B}dd{margin:0;overflow-wrap:anywhere}
        code{font:12px ui-monospace,monospace}
        .warning{color:#F2555A;font-weight:600}
        p{margin:16px 0 0;color:#8E939B}
        """
}
