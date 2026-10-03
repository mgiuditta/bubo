import Foundation
import Observation

/// The setup of the Secondo cervello as a conversation with the model the user picks in the chip, about the folder the
/// user chose: Bubo gives it its standards and that folder, the model interviews the user and proposes its settings.
/// The model never picks the folder, and only the user's confirmation applies the proposal.
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
                                         isConfigured: current != nil, isNew: isNew)
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

    /// Applies the proposal the user confirmed: creates the folder when asked, then chooses it with its settings.
    ///
    /// - Throws: A file system error when the new folder cannot be created, or `CocoaError(.fileNoSuchFile)` when the
    ///   folder to use does not exist.
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
        \(conversation.isEmpty ? "(Nessun messaggio: apri tu la conversazione.)" : conversation)

        Scrivi solo il tuo prossimo messaggio all'utente.
        """
    }

    /// Bubo's standards for the Secondo cervello and the folder the user chose, for the model: `isConfigured` when it
    /// is already the Secondo cervello, `isNew` when Bubo is to create it.
    static func instructions(folder: SecondBrainLocation, isConfigured: Bool, isNew: Bool) -> String {
        let folders = folder.topFolders()
        let listed = folders.isEmpty ? "nessuna sottocartella" : folders.joined(separator: ", ")
        let kind = folder.isObsidianVault ? "vault di Obsidian" : "cartella di note"
        let situation = if isConfigured {
            """
            È il Secondo cervello già configurato: cartelle di primo livello \(listed); escluse \(folder.excludedFolders), \
            prioritarie \(folder.priorityFolders), persone \(folder.people), progetti \(folder.projects). Dillo \
            all'utente («è quella già configurata»), riassumi in breve come è configurata, chiedi se gli funziona e \
            proponi miglioramenti concreti, oppure di lasciarla così.
            """
        } else if isNew {
            """
            È un Secondo cervello nuovo, che Bubo creerà con le cartelle \
            \(SecondBrainProposal.standardFolders.joined(separator: ", ")). Fai domande specifiche su come vuole \
            organizzarlo e su cosa ci metterà.
            """
        } else {
            """
            È una cartella di note che l'utente ha già (\(kind)), con le cartelle di primo livello \(listed). \
            Configurala con lui partendo da queste cartelle.
            """
        }
        return """
        Sei l'assistente che configura il Secondo cervello di Bubo, un'app per Mac, in una conversazione con \
        l'utente. Parla in italiano, in modo breve e personale. Il Secondo cervello deve essere fatto su misura: \
        scopri come lo vuole l'utente intervistandolo, non con un questionario fisso.

        ## Gli standard di Bubo
        - Il Secondo cervello è una cartella di note Markdown dell'utente: un vault di Obsidian o qualunque altra. \
        Obsidian può restare chiuso.
        - Bubo legge le note solo quando le cerca e scrive solo nella cartella `Bubo` alla radice (note, riassunti \
        delle Sessioni, Riunioni). Non tocca mai le altre note.
        - Cartelle escluse: restano dove sono ma Bubo non le legge (di solito archivi, allegati, modelli).
        - Cartelle prioritarie: quando la ricerca trova note in più cartelle, queste vengono prima.
        - Persone e progetti: le note che li nominano vengono prima nella ricerca.

        ## La cartella scelta dall'utente
        \(folder.path)
        \(situation)
        La cartella l'ha scelta l'utente: non proporne altre e non metterla in discussione.

        ## Come intervistare
        - Una sola domanda per messaggio, e accanto la risposta che consiglieresti tu, così può dire solo «sì».
        - Segui i rami uno alla volta e non passare oltre finché uno non è chiaro: cosa ci mette, come è \
        organizzata o come vuole organizzarla, cosa cerca più spesso, cosa va escluso, cosa conta di più, con chi \
        lavora, quali progetti segue.
        - Se una risposta si ricava dalle cartelle, non chiederla: dilla e chiedi conferma.
        - Proponi solo quando hai capito abbastanza; di solito servono da tre a sei domande.

        Usa solo cartelle di primo livello per escluse e prioritarie. Non usare strumenti per scrivere file: Bubo \
        applica la proposta solo dopo la conferma dell'utente.

        Quando hai una proposta, spiegala in una frase e chiudi il messaggio con un solo blocco così, \
        con JSON valido:
        ```\(SecondBrainProposal.fence)
        {"azione": "\(isNew ? "crea" : "usa")", "cartella": "\(folder.path)", "escluse": [], "prioritarie": [], \
        "persone": [], "progetti": []}
        ```
        L'utente vede un bottone per applicarla; se cambia idea, proponi un nuovo blocco.
        """
    }
}
