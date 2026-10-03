import Foundation
import Observation

/// The setup of the Secondo cervello as an interview in rounds with the model the user picks in the chip, about the
/// folder the user chose: Bubo gives it its standards and the facts it found, the model asks for the decisions, then
/// shows the map with the Profilo and the Regole. The model never picks the folder, and only the user's yes applies the
/// proposal and writes `Bubo/Profilo.md` and `Bubo/Regole.md`: nothing is written before.
@Observable
final class SecondBrainConversation {
    /// One message of the conversation.
    struct Turn: Identifiable {
        let id = UUID()
        /// Whether the user wrote it; the model did otherwise.
        let isUser: Bool
        let text: String
    }

    /// The messages so far, the model's without their proposal block.
    private(set) var turns: [Turn] = []
    /// The last settings the model proposed and the user has not applied yet.
    private(set) var proposal: SecondBrainProposal?
    /// Whether the model is writing its next message.
    private(set) var isWaiting = false
    /// The folder the user chose, `nil` until the conversation starts.
    private(set) var folder: URL?
    /// Whether ``folder`` is to be created rather than used as it is.
    private(set) var isNew = false

    /// Who answers, with the model picked in its chip.
    let questions: QuestionModel
    @ObservationIgnored private let secondBrain: SecondBrain
    @ObservationIgnored private var instructions = ""

    /// Creates the conversation about `secondBrain`, asked through `questions`.
    init(questions: QuestionModel, secondBrain: SecondBrain) {
        self.questions = questions
        self.secondBrain = secondBrain
    }

    /// Starts the conversation about `folder`, which the user chose, and lets the model open it; `isNew` when it is
    /// to be created.
    func start(with folder: URL, isNew: Bool) {
        guard self.folder == nil, !isWaiting else { return }
        self.folder = folder
        self.isNew = isNew
        let current = secondBrain.location.flatMap { $0.path == folder.standardizedFileURL.path ? $0 : nil }
        instructions = Self.instructions(folder: current ?? SecondBrainLocation(folder: folder),
                                         isConfigured: current != nil, isNew: isNew, method: Self.method(in: folder),
                                         callApps: CallService.installed().map(\.name).sorted())
        ask()
    }

    /// Sends the user's `text` and asks the model for its answer.
    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWaiting else { return }
        turns.append(Turn(isUser: true, text: text))
        proposal = nil
        ask()
    }

    /// Takes the model's answer once it ends; called when `questions` stops answering.
    func receive() {
        guard isWaiting, !questions.isAnswering else { return }
        isWaiting = false
        guard questions.failure == nil else { return }
        let answer = questions.answer
        // Only the latest answer's proposal can be applied: a stale one is never offered.
        proposal = SecondBrainProposal(in: answer).map { proposed in
            // The folder is the user's choice, whatever the block says.
            var proposed = proposed
            proposed.path = folder?.path ?? proposed.path
            proposed.action = isNew ? .create : .use
            return proposed
        }
        let prose = SecondBrainProposal.prose(of: answer)
        if !prose.isEmpty { turns.append(Turn(isUser: false, text: prose)) }
    }

    /// Applies the proposal the user said yes to: creates the folder when asked, writes the Profilo and the Regole,
    /// then chooses the folder with its settings.
    ///
    /// - Throws: A file system error when the new folder or a file cannot be written, `NoteWriter.Failure` when `Bubo/`
    ///   leads out of the folder, or `CocoaError(.fileNoSuchFile)` when the folder to use does not exist.
    func apply() throws {
        guard let proposal else { return }
        let folder = proposal.folder
        switch proposal.action {
        case .create:
            for name in SecondBrainProposal.standardFolders {
                try FileManager.default.createDirectory(at: folder.appending(path: name), withIntermediateDirectories: true)
            }
        case .use:
            guard SecondBrainLocation(folder: folder).isReachable else { throw CocoaError(.fileNoSuchFile) }
        }
        try NoteWriter(root: folder).writeSetup(profile: proposal.profile, rules: proposal.rules)
        secondBrain.choose(folder)
        secondBrain.excludeOnly(Set(proposal.excludedFolders))
        secondBrain.prioritizeOnly(Set(proposal.priorityFolders))
        secondBrain.prioritize(people: proposal.people, projects: proposal.projects)
        self.proposal = nil
    }

    private func ask() {
        isWaiting = true
        questions.askWithChosenModel(Self.prompt(instructions: instructions, turns: turns))
    }

    /// What the model reads at each turn: the instructions, then the conversation so far.
    static func prompt(instructions: String, turns: [Turn]) -> String {
        let conversation = turns.map { "\($0.isUser ? "Utente" : "Tu"): \($0.text)" }.joined(separator: "\n\n")
        return """
        \(instructions)

        ## Conversazione finora
        \(conversation.isEmpty ? "(Nessun messaggio: apri tu con il primo round.)" : conversation)

        Scrivi solo il tuo prossimo messaggio all'utente.
        """
    }

    /// How the model interviews: the user's `Bubo/Intervista.md` in `folder` when it holds any text, else Bubo's
    /// ``defaultMethod``.
    static func method(in folder: URL) -> String {
        let custom = NoteWriter.setupText(NoteWriter.interviewPath, in: folder)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.flatMap { $0.isEmpty ? nil : $0 } ?? defaultMethod
    }

    /// Bubo's interview, after the method of `grill-me` (#651): rounds with the whole frontier, facts found by Bubo,
    /// decisions left to the user, the map shown until the user says yes.
    static let defaultMethod = """
        Intervista l'utente finché non avete la stessa idea. Tieni in testa un albero di decisioni: ogni decisione \
        apre quelle che dipendono da lei.

        Lavora a round. La frontiera sono le decisioni i cui prerequisiti sono già decisi. In ogni round fai tutta la \
        frontiera insieme, numerata, e per ogni domanda dai la tua risposta consigliata, così l'utente può rispondere \
        solo «sì» o con i numeri da cambiare. Poi aspetta. Le risposte cambiano l'albero: ricalcola la frontiera e fai \
        il round dopo. Una domanda che dipende da un'altra ancora aperta va nel round successivo.

        I fatti li ha già cercati Bubo (cartelle, app installate, Profilo e Regole esistenti): non chiederli mai, dilli \
        e basati su quelli. Le decisioni sono dell'utente: proponile e aspetta.

        Rami da coprire, ognuno con le domande che ne dipendono:
        - Chi è: lavoro, ruolo, contesto, lingua delle note.
        - Cosa tracciare: progetti, aree, persone, riunioni, decisioni, obiettivi, apprendimento, altro; per ognuno \
        dove va e cosa ci scrive.
        - Storico: note da portare dentro o già nella cartella; cosa è archivio da escludere e cosa conta di più.
        - Strumenti: con quali app lavora (riunioni, ticket, mail, calendario, chat).
        - Routine: come apre e chiude giornata e settimana, cosa vuole trovare pronto.
        - Cosa salvare da solo: quali fatti Bubo annota senza chiedere e cosa deve chiedere prima.

        Quando la frontiera è vuota mostra la mappa: albero delle cartelle, cosa va dove, anteprima di Profilo e \
        Regole. Chiedi se va bene e correggila finché l'utente non dice sì.
        """

    /// Bubo's standards for the Secondo cervello, the facts about the folder the user chose and `method`, for the model:
    /// `isConfigured` when it is already the Secondo cervello, `isNew` when Bubo is to create it, `callApps` the call
    /// apps on this Mac.
    static func instructions(folder: SecondBrainLocation, isConfigured: Bool, isNew: Bool,
                             method: String = defaultMethod, callApps: [String] = []) -> String {
        let folders = folder.topFolders()
        let listed = folders.isEmpty ? "nessuna sottocartella" : folders.joined(separator: ", ")
        let kind = folder.isObsidianVault ? "vault di Obsidian" : "cartella di note"
        let situation = if isConfigured {
            """
            È il Secondo cervello già configurato: cartelle di primo livello \(listed); escluse \(folder.excludedFolders), \
            prioritarie \(folder.priorityFolders), persone \(folder.people), progetti \(folder.projects). Dillo \
            all'utente («è quella già configurata») e parti da com'è: chiedi solo cosa cambiare.
            """
        } else if isNew {
            """
            È un Secondo cervello nuovo, che Bubo creerà con le cartelle \
            \(SecondBrainProposal.standardFolders.joined(separator: ", ")).
            """
        } else {
            "È una cartella di note che l'utente ha già (\(kind)), con le cartelle di primo livello \(listed)."
        }
        return """
        Sei l'assistente che configura il Secondo cervello di Bubo, un'app per Mac, intervistando l'utente. Parla in \
        italiano, in modo breve e personale. Il Secondo cervello deve essere fatto su misura per lui.

        ## Gli standard di Bubo
        - Il Secondo cervello è una cartella di note Markdown dell'utente: un vault di Obsidian o qualunque altra. \
        Obsidian può restare chiuso.
        - Bubo legge le note solo quando le cerca e scrive solo nella cartella `Bubo` alla radice (note, riassunti \
        delle Sessioni, Riunioni). Non tocca mai le altre note.
        - `\(NoteWriter.profilePath)`: chi è l'utente, in breve. `\(NoteWriter.rulesPath)`: come tenere il Secondo \
        cervello, cosa va dove, cosa Bubo salva da solo e cosa chiede prima. Bubo li dà a ogni chat: insieme stanno \
        sotto le 1.500 parole.
        - Cartelle escluse: restano dove sono ma Bubo non le legge (di solito archivi, allegati, modelli).
        - Cartelle prioritarie: quando la ricerca trova note in più cartelle, queste vengono prima.
        - Persone e progetti: le note che li nominano vengono prima nella ricerca.

        ## I fatti che Bubo ha trovato
        Cartella scelta dall'utente: \(folder.path)
        \(situation)
        App per le riunioni su questo Mac: \(callApps.isEmpty ? "nessuna" : callApps.joined(separator: ", ")).
        \(currentSetup(in: folder.url))
        La cartella l'ha scelta l'utente: non proporne altre e non metterla in discussione.

        ## Come intervistare
        \(method)

        ## La proposta
        Non usare strumenti per scrivere file: Bubo scrive solo dopo il sì dell'utente. Usa solo cartelle di primo \
        livello per escluse e prioritarie. Quando mostri la mappa, chiudi il messaggio con un solo blocco così, con \
        JSON valido; profilo e regole sono il Markdown completo dei due file:
        ```\(SecondBrainProposal.fence)
        {"azione": "\(isNew ? "crea" : "usa")", "cartella": "\(folder.path)", "escluse": [], "prioritarie": [], \
        "persone": [], "progetti": [], "profilo": "", "regole": ""}
        ```
        L'utente vede la mappa e un bottone per dire sì; se chiede modifiche, mostra la mappa corretta con un nuovo \
        blocco.
        """
    }

    /// The Profilo and the Regole already in `folder`, for the model to start from; empty when there are none.
    private static func currentSetup(in folder: URL) -> String {
        [("Profilo attuale", NoteWriter.profilePath), ("Regole attuali", NoteWriter.rulesPath)]
            .compactMap { title, path in
                guard let text = NoteWriter.setupText(path, in: folder) else { return nil }
                return "\(title) (`\(path)`):\n\(text.prefix(6_000))"
            }
            .joined(separator: "\n\n")
    }
}
