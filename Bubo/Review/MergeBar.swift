import SwiftUI

/// The line of Fondi under the revisione's header: Annulla merge while the merge can be undone, else the
/// conflicts the agent is resolving, else why Fondi cannot go ahead, with Risolvi con l'agente for conflicts,
/// else the commit message to edit.
struct MergeBar: View {
    let preview: MergePreview?
    /// Whether every blocco is accepted.
    let canMerge: Bool
    /// Until when the merge just made can be undone; `nil` before Fondi.
    let undoDeadline: Date?
    /// Why the last Fondi or Annulla merge failed.
    let failure: String?
    /// The branch whose conflicts the agent is resolving in the Sessione's worktree; `nil` otherwise.
    let resolvingBranch: String?
    @Binding var message: String
    let isEditingMessage: FocusState<Bool>.Binding
    let undo: () -> Void
    /// Asks the agent to resolve the conflicts; `nil` while it cannot, as when the agent works.
    let resolve: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            if let undoDeadline {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                        .accessibilityHidden(true)
                    Text("Fusa in \(preview?.branch ?? "") con un commit locale, senza push.")
                        .font(Typography.body(size: 12.5))
                    Text(timerInterval: Date.now...max(undoDeadline, .now), countsDown: true)
                        .font(Typography.mono(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                    Spacer(minLength: Spacing.small)
                    Button("Annulla merge", action: undo)
                        .keyboardShortcut("z", modifiers: .command)
                }
            } else if let resolvingBranch {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                    Image(systemName: "arrow.triangle.merge")
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                    Text("L'agente risolve i conflitti con \(resolvingBranch) nella copia della Sessione. Poi rivedi i blocchi nuovi.")
                        .font(Typography.body(size: 12.5))
                }
            } else if let obstacle = preview?.obstacle, obstacle != .nothingToMerge || canMerge {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    warning(obstacle.localizedDescription)
                    if case .conflicts = obstacle {
                        Spacer(minLength: Spacing.small)
                        Button("Risolvi con l'agente") { resolve?() }
                            .disabled(resolve == nil)
                            .help("Porta il branch del checkout nella copia della Sessione e chiede all'agente di risolvere i conflitti lì")
                    }
                }
            } else if canMerge {
                TextField("Messaggio del commit", text: $message, axis: .vertical)
                    .font(Typography.mono(size: 12))
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused(isEditingMessage)
            }
            if let failure { warning(failure) }
        }
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.danger)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(Typography.body(size: 12.5))
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
        }
    }
}
