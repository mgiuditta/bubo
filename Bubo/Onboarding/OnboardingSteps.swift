import SwiftUI

/// The two steps of the first launch, 1 Progetto → 2 Cosa fare: a done step has a check, the one still missing is
/// highlighted once the other is under way.
struct OnboardingSteps: View {
    let flow: OnboardingFlow

    var body: some View {
        HStack(spacing: Spacing.small) {
            step(.project, number: 1, title: "Progetto")
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            step(.question, number: 2, title: "Cosa fare")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.steps")
    }

    private func step(_ step: OnboardingFlow.Step, number: Int, title: LocalizedStringResource) -> some View {
        let isDone = flow.isDone(step)
        let isHighlighted = flow.highlightedStep == step
        return HStack(spacing: Spacing.xxSmall) {
            Group {
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                } else {
                    Text(number, format: .number)
                        .font(Typography.mono(size: 11, weight: .medium))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(isHighlighted ? Palette.accent : Palette.line))
                }
            }
            .foregroundStyle(isDone || isHighlighted ? Palette.accent : Palette.textSecondary)
            Text(title)
                .font(Typography.body(size: 13, weight: isHighlighted ? .semibold : .regular))
                .foregroundStyle(isHighlighted || isDone ? Palette.textPrimary : Palette.textSecondary)
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xxSmall)
        .overlay {
            // Not color alone: the step to do next also gets a frame and a bolder title.
            if isHighlighted { Capsule().strokeBorder(Palette.accent) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Passo \(number) di 2: \(Text(title))"))
        .accessibilityValue(isDone ? Text("Fatto") : isHighlighted ? Text("Prossimo") : Text("Da fare"))
    }
}
