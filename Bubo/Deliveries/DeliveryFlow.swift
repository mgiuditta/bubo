import AppKit
import CryptoKit
import os

/// The foglio di Consegna of one Sessione (spec 24, Interfaccia): it prepares the preview, keeps what the user chose,
/// and at Condividi… writes the `.bubo` and opens the Condividi of macOS.
@Observable
final class DeliveryFlow {
    /// Where the foglio is.
    enum Phase {
        /// Reading, cleaning, scanning and bundling the Sessione.
        case preparing
        /// The preview is shown.
        case ready(DeliveryBuilder.Preview)
        /// Writing and encrypting the `.bubo`.
        case building(DeliveryBuilder.Preview)
        /// The Condividi of macOS is open.
        case sharing(DeliveryBuilder.Preview)
        /// The Sessione cannot be delivered, with why.
        case failed(String)
    }

    let session: Session
    private(set) var phase = Phase.preparing
    /// The Macchina and the decisions; empty until the preview is ready.
    private(set) var choices = DeliveryChoices(findings: [])
    /// The line "Mostra nella conversazione" scrolled to.
    var shownLine: String?
    /// Why the last Condividi… did not go, shown in the foglio's footer.
    private(set) var shareFailure: String?
    /// Whether the foglio is done: delivered, so it closes.
    private(set) var isDelivered = false

    private let source: DeliveryBuilder.Source?
    private let builder: DeliveryBuilder
    private let deliveries: DeliveriesController
    private var share: DeliveryShare?
    private let log = Logger(subsystem: "com.mgiuditta.bubo", category: "deliveries")

    /// Creates the foglio of `session`, whose files `builder` reads from `source`; `nil` when the Sessione has no
    /// conversation or no folder yet.
    init(session: Session, source: DeliveryBuilder.Source?, builder: DeliveryBuilder = DeliveryBuilder(),
         deliveries: DeliveriesController) {
        self.session = session
        self.source = source
        self.builder = builder
        self.deliveries = deliveries
    }

    /// The foglio of `session` with the files of this Mac: Bubo's copy and `~/.claude/projects`.
    static func live(for session: Session, deliveries: DeliveriesController) -> DeliveryFlow {
        let source: DeliveryBuilder.Source? = if let conversation = session.conversations.last,
            let workspace = session.workspace, let mirror = try? ConversationStore.defaultFile() {
            DeliveryBuilder.Source(
                title: session.title, conversationID: conversation, worktree: workspace.folder,
                branch: workspace.branch, base: workspace.base,
                home: URL.homeDirectory.path, mirror: mirror,
                claudeProjects: URL.homeDirectory.appending(path: ".claude/projects", directoryHint: .isDirectory)
            )
        } else {
            nil
        }
        return DeliveryFlow(session: session, source: source, deliveries: deliveries)
    }

    /// The preview, while there is one.
    var preview: DeliveryBuilder.Preview? {
        switch phase {
        case let .ready(preview), let .building(preview), let .sharing(preview): preview
        case .preparing, .failed: nil
        }
    }

    /// The Biglietti the foglio lists under A chi.
    var tickets: [ReceivedTicket] { deliveries.tickets }

    /// Whether the user can press Condividi…: something to send, a Macchina and every secret decided.
    var canShare: Bool {
        guard case .ready = phase else { return false }
        return choices.canShare
    }

    /// Whether the content passes the size Messaggi sends.
    var isLarge: Bool {
        (preview?.estimatedSize ?? 0) > DeliveryBuilder.largeSize
    }

    /// Reads the Sessione and prepares the preview.
    func prepare() async {
        await deliveries.load()
        guard let source else {
            phase = .failed(String(localized: "Questa Sessione non ha ancora una conversazione da consegnare."))
            return
        }
        do {
            let preview = try await builder.prepare(source, person: deliveries.person)
            choices = DeliveryChoices(findings: preview.findings, findingsInBranch: preview.findingsInBranch)
            phase = .ready(preview)
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    /// Chooses the Macchina of `ticket`; one whose key changed is not chosen.
    func choose(_ ticket: ReceivedTicket) {
        choices.choose(ticket)
    }

    /// Decides `decision` for the possible secret `finding`.
    func decide(_ decision: DeliveryChoices.Decision, for finding: SecretScanner.Finding) {
        choices.decide(decision, for: finding.id)
    }

    /// Mostra nella conversazione: scrolls the Conversazione ripulita to the first line of `finding`.
    func show(_ finding: SecretScanner.Finding) {
        shownLine = finding.locations.first { $0.file == SessionFiles.transcriptName && $0.lineID != nil }?.lineID
    }

    /// Condividi…: writes the `.bubo` for the chosen Macchina and opens the Condividi of macOS next to `anchor`.
    func share(from anchor: NSView) async {
        choices.keepRecipient(among: deliveries.tickets)
        guard case let .ready(preview) = phase, choices.canShare,
              let ticket = deliveries.tickets.first(where: { $0.id == choices.recipient }),
              let recipient = try? P256.KeyAgreement.PublicKey(x963Representation: ticket.publicKey)
        else { return }
        shareFailure = nil
        phase = .building(preview)
        do {
            let key = try await deliveries.sealingKey()
            let file = try await builder.build(preview, removing: choices.removedSecrets, person: deliveries.person,
                                               machine: deliveries.machine, for: recipient, sealedBy: key)
            // The file goes with its own folder when the Condividi closes; the preparation stays for another try.
            let share = DeliveryShare(file: file, folder: file.deletingLastPathComponent()) { [weak self] outcome in
                self?.finish(outcome, preview: preview, to: ticket)
            }
            self.share = share
            phase = .sharing(preview)
            share.show(relativeTo: anchor)
        } catch {
            log.error("Consegna not written: \(String(describing: error), privacy: .public)")
            shareFailure = String(localized: "La Consegna non si scrive. Riprova.")
            phase = .ready(preview)
        }
    }

    /// Annulla, or the foglio closed: the preparation folder goes.
    func discard() {
        share?.finish(.cancelled)
        preview?.discard()
    }

    private func finish(_ outcome: DeliveryShare.Outcome, preview: DeliveryBuilder.Preview, to ticket: ReceivedTicket) {
        share = nil
        switch outcome {
        case let .shared(channel):
            preview.discard()
            deliveries.noteDelivery(of: session.id, through: channel, to: ticket)
            isDelivered = true
        case .failed:
            shareFailure = String(localized: "Il Condividi non l'ha mandata. Riprova, anche con un altro mezzo.")
            phase = .ready(preview)
        case .cancelled:
            phase = .ready(preview)
        }
    }

    private static func message(for error: DeliveryBuilder.Failure) -> String {
        switch error {
        case .conversationMissing:
            String(localized: "La conversazione di questa Sessione non è nella copia di Bubo.")
        case .mirrorUnreadable:
            String(localized: "La copia delle conversazioni di Bubo non si legge.")
        case let .cleaning(failure):
            failure.localizedDescription
        case .branch:
            String(localized: "Il ramo della Sessione non si legge con git.")
        case .scannerMissing:
            String(localized: "Mancano le regole per cercare i segreti. Reinstalla Bubo.")
        }
    }
}
