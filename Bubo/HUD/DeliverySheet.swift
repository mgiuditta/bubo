import SwiftUI

/// The foglio di Consegna (spec 24, Interfaccia, variante B): A chi and the two warnings on the left; Da decidere,
/// Cosa esce, Tolto da Bubo and the Conversazione ripulita on the right; in the footer the state, Annulla and
/// Condividi…, off until a Macchina is chosen and every possible secret is decided.
struct DeliverySheet: View {
    @State private var flow: DeliveryFlow
    @Environment(DeliveriesController.self) private var deliveries
    @Environment(\.dismiss) private var dismiss
    @State private var anchor: NSView?

    /// Creates the foglio of `flow`'s Sessione.
    init(flow: DeliveryFlow) {
        _flow = State(initialValue: flow)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Consegna «\(flow.session.title)»")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.medium)
                .accessibilityAddTraits(.isHeader)
            Divider()
            content
            Divider()
            footer
                .padding(Spacing.medium)
        }
        .frame(width: 880, height: 640)
        .task { await flow.prepare() }
        .onChange(of: flow.isDelivered) {
            if flow.isDelivered { dismiss() }
        }
        .onChange(of: flow.choices.undecidedCount) { _, count in
            AccessibilityNotification.Announcement(String(localized: "Da decidere: \(count)")).post()
        }
        .onDisappear { flow.discard() }
        // Here, so a Biglietto added from the foglio shows its code over it.
        .sheet(item: Bindable(deliveries).pendingImport) { pending in
            TicketImportSheet(pending: pending, deliveries: deliveries)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch flow.phase {
        case .preparing:
            LoadingLabel("Ripulisco la Sessione e cerco i segreti…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ErrorText(message: message)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .ready(preview), let .building(preview), let .sharing(preview):
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        DeliveryRecipientList(tickets: flow.tickets, recipient: flow.choices.recipient,
                                              choose: flow.choose) { url in
                            Task { _ = await deliveries.open(url) }
                        }
                        warnings(preview)
                    }
                    .padding(Spacing.medium)
                }
                .frame(width: 300)
                Divider()
                DeliveryContents(preview: preview, flow: flow)
            }
        }
    }

    private func warnings(_ preview: DeliveryBuilder.Preview) -> some View {
        let reasoning = preview.cleaned.removed[.reasoning] ?? 0
        let name = flow.tickets.first { $0.id == flow.choices.recipient }?.person
            ?? String(localized: "chi riceve")
        return VStack(alignment: .leading, spacing: Spacing.small) {
            WarningText(title: "Il ragionamento non passa.",
                        detail: "Con un altro account i \(reasoning) blocchi di ragionamento non si riprendono: \(name) vede messaggi, strumenti e ramo.")
            WarningText(title: "Una volta consegnata, è sua.",
                        detail: "Non si revoca, non scade e non avvisa quando la apre.")
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.small) {
            Text(status)
                .font(.callout)
                .foregroundStyle(flow.shareFailure == nil && !flow.isLarge ? Palette.textSecondary : Palette.danger)
                .lineLimit(2)
            Spacer(minLength: Spacing.small)
            if case .building = flow.phase {
                LoadingLabel("Cifro la Consegna…")
            }
            Button("Annulla", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Condividi…") {
                guard let anchor else { return }
                Task { await flow.share(from: anchor) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!flow.canShare)
            .help(flow.canShare ? Text("Apre il Condividi di macOS") : Text(status))
            .accessibilityHint(flow.canShare ? Text("Apre il Condividi di macOS") : Text(status))
            .background { SharingAnchor { anchor = $0 } }
        }
    }

    /// The footer's state: what is missing, else the size, with the warning past 100 MB.
    private var status: String {
        if let failure = flow.shareFailure { return failure }
        guard let preview = flow.preview else { return "" }
        switch flow.choices.missing {
        case .recipient:
            return String(localized: "Scegli a chi")
        case .decisions:
            return String(localized: "Decidi i possibili segreti")
        case .removalsInBranch:
            return String(localized: "Un segreto da togliere è anche nelle modifiche non salvate: toglilo dal file e riapri, oppure scegli Lascia.")
        case nil:
            let size = preview.estimatedSize.formatted(.byteCount(style: .file))
            return flow.isLarge
                ? String(localized: "Grande (\(size)): Messaggi potrebbe non mandarla. Usa AirDrop o Salva sul disco.")
                : String(localized: "Pronta: \(size)")
        }
    }
}

/// A warning always visible in the foglio: a bold first sentence, then the rest.
private struct WarningText: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(title).bold()
                Text(detail).foregroundStyle(Palette.textSecondary)
            }
            .font(.callout)
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .accessibilityElement(children: .combine)
    }
}

/// Why the foglio cannot go on, in place of the preview.
private struct ErrorText: View {
    let message: String

    var body: some View {
        Label {
            Text(verbatim: message)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(Palette.danger)
        .padding(Spacing.large)
    }
}
