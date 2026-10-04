import AppIntents
import Foundation

/// Where "Chiedi a Bubo" sends its Domanda: the Domanda of the HUD, whose answer the Orb of the Panel follows.
protocol QuestionAsking: AnyObject, Sendable {
    /// Asks `text` with `attachments` as a new Domanda, replacing any answer in progress.
    func ask(_ text: String, attachments: [Allegato])
}

extension QuestionModel: QuestionAsking {}

/// "Chiedi a Bubo", from Spotlight and Comandi rapidi (spec 09): a text and optional files become a Domanda, sent at
/// once without opening the HUD.
struct AskBuboIntent: AppIntent {
    static let title: LocalizedStringResource = "Chiedi a Bubo"
    static let description = IntentDescription("Fa una Domanda a Bubo, con file di testo facoltativi. La risposta compare accanto all'Orb, o nella finestra di Bubo.")
    /// Bubo answers in the background: the HUD stays closed.
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Domanda", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "File", default: [])
    var files: [IntentFile]

    static var parameterSummary: some ParameterSummary {
        Summary("Chiedi a Bubo \(\.$text)") {
            \.$files
        }
    }

    /// Where the Domande go: the Domanda of the HUD, set at launch before any intent runs; tests set a stand-in.
    @MainActor static var questions: (any QuestionAsking)?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            throw $text.needsValueError("Che cosa vuoi chiedere a Bubo?")
        }
        let attachments = try files.map(Self.attachment)
        try await Self.ask(question, attachments: attachments)
        // Not a silent run: with the Panel hidden nothing else says that Bubo got the Domanda.
        return .result(dialog: "Domanda inviata a Bubo.")
    }

    /// Asks `question` with `attachments` through `questions`.
    ///
    /// - Throws: `AskBuboError.notReady` before launch set `questions`.
    @MainActor private static func ask(_ question: String, attachments: [Allegato]) throws {
        guard let questions else { throw AskBuboError.notReady }
        questions.ask(question, attachments: attachments)
    }

    /// The Allegato of `file`: its name and its text, read now, since the file may not stay reachable.
    ///
    /// - Throws: `AskBuboError.notText` when the file is not UTF-8 text.
    private static func attachment(from file: IntentFile) throws -> Allegato {
        guard let text = String(data: file.data, encoding: .utf8) else {
            throw AskBuboError.notText(file.filename)
        }
        return Allegato(name: file.filename, text: text)
    }
}

/// Why "Chiedi a Bubo" did not send its Domanda.
enum AskBuboError: Error, CustomLocalizedStringResourceConvertible {
    /// A file that is not text, named by its file name: Bubo reads only text files from here, for now.
    case notText(String)
    /// Bubo is still starting.
    case notReady

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .notText(name): "«\(name)» non è un file di testo. Trascinalo sull'Orb per allegarlo."
        case .notReady: "Bubo si sta avviando. Riprova tra un attimo."
        }
    }
}
