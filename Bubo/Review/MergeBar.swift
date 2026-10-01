import SwiftUI

/// The line of Fondi under the revisione's header: Annulla merge while the merge can be undone, else why Fondi
/// cannot go ahead, else the commit message to edit.
struct MergeBar: View {
    let preview: MergePreview?
    /// Whether every blocco is accepted.
    let canMerge: Bool
    /// Until when the merge just made can be undone; `nil` before Fondi.
    let undoDeadline: Date?
    /// Why the last Fondi or Annulla merge failed.
    let failure: String?
    @Binding var message: String
    let isEditingMessage: FocusState<Bool>.Binding
    let undo: () -> Void

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
            } else if let obstacle = preview?.obstacle, obstacle != .nothingToMerge || canMerge {
                warning(obstacle.localizedDescription)
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
