import SwiftUI

/// How Bubo shows an error: what happened, what to do, and a button that does it.
///
/// All three are required, so no error can reach the screen without a way out.
struct ErrorNotice: View {
    private let problem: LocalizedStringKey
    private let remedy: LocalizedStringKey
    private let actionTitle: LocalizedStringKey
    private let action: () -> Void

    /// Creates a notice for an error.
    ///
    /// - Parameters:
    ///   - problem: What happened, such as "Claude Code non risponde".
    ///   - remedy: What the user can do, such as "Riavvialo e riprova".
    ///   - actionTitle: The button that does it, such as "Riprova".
    ///   - action: Runs when the button is pressed.
    init(_ problem: LocalizedStringKey, remedy: LocalizedStringKey, actionTitle: LocalizedStringKey,
         action: @escaping () -> Void) {
        self.problem = problem
        self.remedy = remedy
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.danger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(problem)
                    .font(Typography.body(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(remedy)
                    .font(Typography.body(size: 13))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: Spacing.small)
            Button(actionTitle, action: action)
        }
        .padding(Spacing.small)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .strokeBorder(Palette.danger.opacity(0.4))
        }
        .accessibilityElement(children: .contain)
    }
}

