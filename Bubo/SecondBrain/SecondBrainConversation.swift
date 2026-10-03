import Foundation
import Observation

/// The setup of the Secondo cervello as a conversation with the model the user picks in the chip: Bubo gives it its
/// standards and the folders on this Mac, the model asks what it needs and proposes either a folder the user has or a
/// new one. Only the user's confirmation applies the proposal.
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

    /// Who answers, with the model picked in its chip.
    let questions: QuestionModel
    @ObservationIgnored private let secondBrain: SecondBrain
    @ObservationIgnored private let instructions: String

    /// Creates the conversation about `secondBrain`, asked through `questions`.
    init(questions: QuestionModel, secondBrain: SecondBrain) {
        self.questions = questions
        self.secondBrain = secondBrain
        let current = secondBrain.location
        let vaults = SecondBrainLocation.suggestedVaults()
            .filter { $0.standardizedFileURL.path != current?.path }
            .map(SecondBrainLocation.init(folder:))
        instructions = Self.instructions(current: current, vaults: vaults,
                                         home: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    /// Lets the model open the conversation.
    func start() {
        guard turns.isEmpty, !isWaiting else { return }
        ask()
    }

    /// Sends the user's `text` and asks the model for its answer.
    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWaiting else { return }
        turns.append(Turn(isUser: true, text: text))
        ask()
    }

    /// Takes the model's answer once it ends; called when `questions` stops answering.
    func receive() {
        guard isWaiting, !questions.isAnswering else { return }
        isWaiting = false
        guard questions.failure == nil else { return }
        let answer = questions.answer
        if let proposed = SecondBrainProposal(in: answer) { proposal = proposed }
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

    /// Bubo's standards for the Secondo cervello and the folders found on this Mac, for the model.
    static func instructions(current: SecondBrainLocation?, vaults: [SecondBrainLocation], home: String) -> String {
        func describe(_ location: SecondBrainLocation) -> String {
            let kind = location.isObsidianVault ? "vault di Obsidian" : "cartella di note"
            let folders = location.topFolders()
            let listed = folders.isEmpty ? "nessuna sottocartella" : folders.joined(separator: ", ")
            return "- \(location.path) (\(kind)); cartelle di primo livello: \(listed)"
        }
        var found: [String] = []
        if let current {
            found.append("Secondo cervello attuale, con escluse \(current.excludedFolders), prioritarie "
                         + "\(current.priorityFolders), persone \(current.people), progetti \(current.projects):")
            found.append(describe(current))
        }
        found.append(vaults.isEmpty ? "Nessun vault di Obsidian trovato sul Mac." : "Vault di Obsidian sul Mac:")
        found += vaults.map(describe)
        return """
        Sei l'assistente che configura il Secondo cervello di Bubo, un'app per Mac, in una conversazione con \
        l'utente. Parla in italiano, in modo breve e personale: una o due domande per messaggio, mai un \
        questionario fisso. Chiedi solo quello che ti serve per capire come lavora l'utente.

        ## Gli standard di Bubo
        - Il Secondo cervello è una cartella di note Markdown dell'utente: un vault di Obsidian o qualunque altra. \
        Obsidian può restare chiuso.
        - Bubo legge le note solo quando le cerca e scrive solo nella cartella `Bubo` alla radice (note, riassunti \
        delle Sessioni, Riunioni). Non tocca mai le altre note.
        - Cartelle escluse: restano dove sono ma Bubo non le legge (di solito archivi, allegati, modelli).
        - Cartelle prioritarie: quando la ricerca trova note in più cartelle, queste vengono prima.
        - Persone e progetti: le note che li nominano vengono prima nella ricerca.
        - Un Secondo cervello nuovo parte con le cartelle \(SecondBrainProposal.standardFolders.joined(separator: ", ")).

        ## Cosa c'è su questo Mac
        Cartella home: \(home)
        \(found.joined(separator: "\n"))

        ## Il tuo compito
        Decidi con l'utente tra due strade: se una cartella sopra sembra sua, diglielo («questo è tuo, \
        controlla») e proponi le impostazioni; altrimenti proponi di crearne una nuova (per esempio \
        \(home)/Documents/Secondo cervello). Usa solo cartelle di primo livello elencate per escluse e prioritarie. \
        Non usare strumenti per scrivere file: Bubo applica la proposta solo dopo la conferma dell'utente.

        Quando hai una proposta, spiegala in una frase e chiudi il messaggio con un solo blocco così, \
        con JSON valido:
        ```\(SecondBrainProposal.fence)
        {"azione": "usa" oppure "crea", "cartella": "/percorso/assoluto", "escluse": [], "prioritarie": [], \
        "persone": [], "progetti": []}
        ```
        L'utente vede un bottone per applicarla; se cambia idea, proponi un nuovo blocco.
        """
    }
}
