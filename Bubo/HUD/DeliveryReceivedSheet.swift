import os
import SwiftUI

/// The foglio "Consegna ricevuta" (spec 24, Destinatario): the Consegna verified, Dove it goes, Cosa arriva, then
/// Scarta · Metti tra le Bozze. Shown only after the header, the sender and the encryption were checked.
struct DeliveryReceivedSheet: View {
    let opened: DeliveryOpener.Opened
    let deliveries: DeliveriesController
    let store: SessionStore
    @Environment(HUDPresenter.self) private var hud
    /// The Progetto the Bozza goes to: the one with the same remote, or the folder chosen or cloned.
    @State private var project: URL?
    /// Looking for the Progetto with the same remote.
    @State private var isLooking = true
    /// Which folder the picker asks for: the Progetto (Scegli…) or where to clone it (Clona).
    @State private var picking: Picking?
    /// Cloning, or importing the branch.
    @State private var isWorking = false
    /// Why Clona did not work.
    @State private var failure: String?

    private enum Picking {
        case project, cloneParent
    }

    private var manifest: DeliveryManifest { opened.manifest }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            header
            whereSection
            contentsSection
            Text("Diventa una Bozza. Quando la avvii, riprende col tuo account e i tuoi Livelli di permesso.")
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            footer
        }
        .padding(Spacing.large)
        .frame(width: 480, alignment: .leading)
        // Only Scarta or Metti tra le Bozze close it: each decides what happens to the content in the clear.
        .interactiveDismissDisabled()
        .fileImporter(isPresented: Binding { picking != nil } set: { if !$0 { picking = nil } },
                      allowedContentTypes: [.folder]) { result in
            guard case let .success(folder) = result else { return }
            switch picking {
            case .project: project = folder
            case .cloneParent: clone(into: folder)
            case nil: break
            }
            picking = nil
        }
        .task { await findProject() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: manifest.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Label("verificata", systemImage: "checkmark.seal")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(Palette.success)
                    .padding(.horizontal, Spacing.xSmall)
                    .padding(.vertical, Spacing.xxSmall / 2)
                    .overlay { Capsule().strokeBorder(Palette.line) }
            }
            Text("da \(manifest.person) · \(manifest.machine)")
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var whereSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text("Dove")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            HStack {
                if let project {
                    Text(verbatim: project.lastPathComponent)
                        .font(Typography.mono(size: 12))
                        .help(project.path)
                } else if isLooking {
                    LoadingLabel("Cerco il Progetto…")
                } else {
                    Text(manifest.remote == nil ? "Scegli la cartella del Progetto." : "Nessun Progetto con lo stesso remote.")
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Button("Scegli…") { picking = .project }
                if manifest.remote != nil, project == nil {
                    Button("Clona") { picking = .cloneParent }
                        .help("Clona il repo in una cartella che scegli")
                }
            }
            .disabled(isWorking)
            if let failure {
                Text(verbatim: failure)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var contentsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text("Cosa arriva")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("\(manifest.counts.messages) messaggi")
            if manifest.counts.subagents > 0 {
                Text("\(manifest.counts.subagents) subagent")
            }
            if manifest.counts.reasoningBlocksRemoved > 0 {
                Text("Il ragionamento di \(manifest.person) non c'è.")
                    .foregroundStyle(Palette.textSecondary)
            }
            if manifest.bundleRef != nil {
                Text("Il ramo \(DeliveryOpener.branchName(person: manifest.person, branch: manifest.branch ?? manifest.title, taken: []))")
            } else {
                Text("Niente ramo: il Progetto non è un repo, o il ramo non aveva modifiche.")
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            if isWorking { LoadingLabel("Preparo la Bozza…") }
            Spacer()
            Button("Scarta", role: .destructive) { deliveries.dismissReceipt() }
                .disabled(isWorking)
            Button("Metti tra le Bozze", action: putAmongDrafts)
                .keyboardShortcut(.defaultAction)
                .disabled(project == nil || isWorking)
                .help(project == nil ? Text("Scegli prima dove va la Consegna") : Text(verbatim: ""))
        }
    }

    /// The Progetto among those Bubo knows whose `origin` is the Consegna's remote.
    private func findProject() async {
        defer { isLooking = false }
        guard let remote = manifest.remote else { return }
        var seen = Set<URL>()
        let known = (store.projects + store.drafts.drafts.map(\.project)).filter { seen.insert($0).inserted }
        if project == nil, let found = await deliveries.opener.project(withRemote: remote, among: known) {
            project = found
        }
    }

    private func clone(into parent: URL) {
        guard let remote = manifest.remote else { return }
        isWorking = true
        failure = nil
        Task {
            defer { isWorking = false }
            do {
                project = try await deliveries.opener.clone(remote, into: parent)
            } catch {
                Logger.sessions.error("Clone failed: \(String(describing: error), privacy: .private)")
                failure = String(localized: "Il repo non si clona. Controlla l'accesso al remote e riprova.")
            }
        }
    }

    /// Imports the branch, then the Bozza with the chip `consegna` among the Bozze of the Progetto.
    private func putAmongDrafts() {
        guard let project else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do throws(DeliveryOpener.Failure) {
                let branch = try await deliveries.opener.importBranch(of: opened, into: project)
                let installed = await ClaudeReadiness.installedVersion()
                var draft = Draft(title: manifest.title, text: "", project: project)
                draft.delivery = DraftDelivery(
                    id: manifest.id, person: manifest.person, machine: manifest.machine, sessionID: manifest.sessionID,
                    branch: branch, baseCommit: manifest.baseCommit,
                    needsClaudeUpdate: DraftDelivery.needsClaudeUpdate(senderVersion: manifest.claudeVersion,
                                                                       installed: installed)
                )
                store.drafts.add(draft)
                deliveries.dismissReceipt(keepingContent: true)
                hud.showDrafts()
            } catch {
                try? FileManager.default.removeItem(at: opened.folder)
                deliveries.receipt?.state = .failed(error)
            }
        }
    }
}
