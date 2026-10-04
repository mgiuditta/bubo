import os
import SwiftUI

/// The sheet of Apri PR (spec 16): the title and the description the model proposes, both editable, the line that
/// closes the issue added by Bubo, the warnings, Bozza off by default, Anteprima with `gh pr create --dry-run`, and
/// a single action, Crea PR, which squashes, pushes and opens the pull request. Nothing is pushed before it.
struct PullRequestSheet: View {
    let session: Session
    let store: SessionStore
    var cli = GitHubCLI()
    var terminal = SystemTerminal()
    @Environment(SessionSummarizer.self) private var summarizer: SessionSummarizer?
    @Environment(\.dismiss) private var dismiss
    @State private var target: PullRequestFlow.Target?
    /// How many blocchi are rejected and were not sent back to the agent.
    @State private var rejectedCount = 0
    @State private var text = PullRequestText(title: "", description: "")
    /// Whether ``text`` holds the proposal, to edit.
    @State private var isTextReady = false
    @State private var isDraft = false
    /// What `gh pr create --dry-run` printed, once asked.
    @State private var preview: String?
    @State private var isPreviewing = false
    @State private var isCreating = false
    /// Why the sheet cannot go ahead, or why the last Anteprima or Crea PR failed.
    @State private var failure: String?
    /// The command that fixes the failure, typed in the Terminale by Apri nel terminale.
    @State private var remedy: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Apri PR · \(session.title)")
                .font(Typography.display(size: 16))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if let target {
                Text(verbatim: "\(target.head) → \(target.base) · \(target.repository.owner)/\(target.repository.name)")
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                warnings(for: target)
            }
            if isTextReady {
                form
            } else if failure == nil {
                LoadingLabel("Preparo la PR…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            if let failure {
                warning(failure)
                if let remedy {
                    Button("Apri nel terminale") { openTerminal(typing: remedy) }
                        .help("Apre il Terminale con «\(remedy)» già scritto: premi Invio per eseguirlo")
                }
            }
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Crea PR", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
                    .help("Unisce il lavoro in un commit sul branch, fa il push e apre la PR")
            }
        }
        .padding(Spacing.medium)
        .frame(width: 520)
        .task { await load() }
    }

    private var canCreate: Bool {
        target != nil && isTextReady && !text.title.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating
            && store.sessions.first { $0.id == session.id }?.isRunning == false
    }

    @ViewBuilder
    private var form: some View {
        TextField("Titolo", text: $text.title)
            .textFieldStyle(.roundedBorder)
            .font(Typography.body(size: 13))
        TextEditor(text: $text.description)
            .font(Typography.mono(size: 12))
            .frame(height: 160)
            .accessibilityLabel("Descrizione")
        if let issue = session.issue {
            Text("Bubo aggiunge «\(PullRequestText.closingLine(for: issue))» in fondo alla descrizione.")
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
        HStack {
            Toggle("Apri come bozza su GitHub", isOn: $isDraft)
                .help("Apre la PR come bozza, che non si può ancora fondere")
            Spacer()
            Button("Anteprima", action: showPreview)
                .disabled(target == nil || isPreviewing)
                .help("Mostra cosa farebbe «gh pr create --dry-run», senza push")
        }
        if let preview {
            ScrollView {
                Text(verbatim: preview)
                    .font(Typography.mono(size: 11))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }
    }

    @ViewBuilder
    private func warnings(for target: PullRequestFlow.Target) -> some View {
        if target.isBaseAssumed {
            warning(String(localized: "Non so da quale branch è partita la Sessione: la PR punta a \(target.base), il branch di default."))
        } else if !target.isIntoDefaultBranch {
            let closing = session.issue.map { " " + String(localized: "«\(PullRequestText.closingLine(for: $0))» resta, ma l'issue non si chiuderà da sola al merge.") } ?? ""
            warning(String(localized: "La PR punta a \(target.base), non al branch di default \(target.defaultBranch).") + closing)
        }
        if rejectedCount > 0 {
            warning(String(localized: "Blocchi rifiutati e non rimandati all'agente: \(rejectedCount). Entrano comunque nella PR."))
        }
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.attention)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(Typography.body(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    /// Where the pull request goes, then the text the model proposes: no model is asked when `gh` cannot open it.
    private func load() async {
        do {
            let found = try await store.pullRequestTarget(of: session.id, with: cli)
            target = found.target
            rejectedCount = found.rejectedCount
        } catch {
            show(error)
            return
        }
        text = await proposedText()
        isTextReady = true
    }

    /// The text the summarizer proposes; without one, the title and the perché of the blocchi.
    private func proposedText() async -> PullRequestText {
        if let summarizer, let text = await summarizer.pullRequestText(of: session.id) { return text }
        let filter = SecretFilter()
        return PullRequestText(title: filter.redacting(session.title), summary: nil,
                               reasons: session.edits.map { filter.redacting($0.why) })
    }

    private func showPreview() {
        guard let target, isTextReady else { return }
        isPreviewing = true
        Task {
            defer { isPreviewing = false }
            do {
                preview = try await store.previewPullRequest(of: session.id, text, isDraft: isDraft, to: target,
                                                             with: cli)
                failure = nil
            } catch {
                show(error)
            }
        }
    }

    private func create() {
        guard let target, isTextReady else { return }
        isCreating = true
        failure = nil
        Task {
            defer { isCreating = false }
            do {
                try await store.openPullRequest(of: session.id, text, isDraft: isDraft, to: target, with: cli)
                dismiss()
            } catch {
                Logger.sessions.error("Pull request not opened: \(String(describing: error), privacy: .private)")
                show(error)
            }
        }
    }

    private func show(_ error: any Error) {
        failure = error.localizedDescription
        remedy = (error as? GitHubCLIError)?.remedy
    }

    private func openTerminal(typing command: String) {
        do {
            try terminal.open(typing: command)
        } catch {
            Logger.sessions.error("Terminal not opened: \(String(describing: error), privacy: .public)")
            failure = error.localizedDescription
            remedy = nil
        }
    }
}
