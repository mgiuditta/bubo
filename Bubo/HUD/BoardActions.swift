import os
import SwiftUI

/// The next step of a Sessione's card on the Board. In Da guardare and PR aperta: Fondi…, which opens the revisione
/// while a blocco is not accepted, else a confirmation that says what it merges into what, ↩ to merge and esc to
/// cancel; and Archivia, which removes the worktree and keeps the branch. In Fusa, Annulla merge while the merge
/// can be undone. Fondi goes through `SessionStore.merge`, like the revisione: the same checks, the same Annulla.
struct BoardActions: View {
    let session: Session
    let column: BoardColumn
    let store: SessionStore
    /// What Fondi… would merge, while its confirmation is shown.
    @State private var proposal: Proposal?
    @State private var isReviewing = false
    @State private var isPreparing = false
    /// Why the last Fondi… or Annulla merge failed.
    @State private var failure: String?

    private var hasContent: Bool {
        column.hasNextStep || store.undoDeadlines[session.id] != nil || failure != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            if column == .fusa, let deadline = store.undoDeadlines[session.id] {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                    Text(timerInterval: Date.now...max(deadline, .now), countsDown: true)
                        .font(Typography.mono(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                    Button("Annulla merge", action: undo)
                }
            } else if column.hasNextStep {
                HStack(spacing: Spacing.xSmall) {
                    if session.workspace?.branch != nil {
                        Button("Fondi…", action: prepareMerge)
                            .disabled(isPreparing || session.isRunning)
                            .help("Mostra cosa unisce e dove, poi chiede conferma")
                    }
                    Button("Archivia") { store.archive(session.id) }
                        .disabled(session.isRunning)
                        .help("Rimuove la copia della Sessione e tiene il branch")
                }
            }
            if let failure {
                Text(verbatim: failure)
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(4)
            }
        }
        .controlSize(.small)
        // Nothing to show takes no room under the card.
        .padding([.horizontal, .bottom], hasContent ? Spacing.xSmall : 0)
        .sheet(isPresented: $isReviewing) {
            ReviewSheet(sessionID: session.id, store: store)
        }
        .sheet(item: $proposal) { proposal in
            MergeConfirmation(session: session, preview: proposal.preview, message: proposal.message, store: store)
        }
    }

    /// Fondi…: the confirmation when every blocco is accepted, the revisione otherwise.
    private func prepareMerge() {
        isPreparing = true
        failure = nil
        Task {
            defer { isPreparing = false }
            do {
                if let merge = try await store.boardMerge(of: session.id) {
                    proposal = Proposal(preview: merge.preview, message: merge.message)
                } else {
                    isReviewing = true
                }
            } catch {
                Logger.sessions.error("Fondi not prepared: \(String(describing: error), privacy: .private)")
                failure = ReviewSheet.explanation(of: error)
            }
        }
    }

    private func undo() {
        Task {
            do {
                try await store.undoMerge(session.id)
            } catch {
                failure = ReviewSheet.explanation(of: error)
            }
        }
    }

    /// What Fondi… would merge.
    private struct Proposal: Identifiable {
        let id = UUID()
        let preview: MergePreview
        let message: String
    }
}

/// The confirmation of Fondi… on the Board: the whole action in words, or why it cannot go ahead.
private struct MergeConfirmation: View {
    let session: Session
    let preview: MergePreview
    let message: String
    let store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var isMerging = false
    @State private var failure: String?

    /// How long the merge can be undone, in words.
    private static let undoWindow = SessionStore.undoWindow.formatted(.units(allowed: [.seconds], width: .wide))

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Fondere «\(session.title)» in \(preview.branch)?")
                .font(Typography.display(size: 16))
                .accessibilityAddTraits(.isHeader)
            if let obstacle = preview.obstacle {
                warning(obstacle.localizedDescription)
            } else {
                Text("Unisce \(session.workspace?.branch ?? "") in \(preview.branch) con un commit locale, senza push. Si annulla solo nei \(Self.undoWindow) successivi, dalla card in Fusa.")
                    .font(Typography.body(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure { warning(failure) }
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Fondi", action: merge)
                    .keyboardShortcut(.defaultAction)
                    .disabled(preview.obstacle != nil || isMerging)
            }
        }
        .padding(Spacing.medium)
        .frame(width: 420)
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.danger)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(Typography.body(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    /// Fondi, with the strategy the Progetto prefers and the message the revisione proposes.
    private func merge() {
        isMerging = true
        failure = nil
        Task {
            defer { isMerging = false }
            do {
                try await store.merge(session.id, message: message, strategy: .preferred(for: session.project))
                dismiss()
            } catch {
                Logger.sessions.error("Fondi failed: \(String(describing: error), privacy: .private)")
                failure = ReviewSheet.explanation(of: error)
            }
        }
    }
}
