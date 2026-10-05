import SwiftUI

/// The three steps of the first launch, 1 Motore → 2 Progetto → 3 Cosa fare: a done step has a check, the one still
/// missing is highlighted: the Motore first, then whichever of the other two is not under way.
struct OnboardingSteps: View {
    let flow: OnboardingFlow

    var body: some View {
        HStack(spacing: Spacing.small) {
            step(.engine, number: 1, title: "Motore")
            arrow
            step(.project, number: 2, title: "Progetto")
            arrow
            step(.question, number: 3, title: "Cosa fare")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.steps")
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.textSecondary)
            .accessibilityHidden(true)
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
        // A merged HStack has no role of its own: without the trait VoiceOver reads it as «Unknown role».
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(Text("Passo \(number) di \(OnboardingFlow.Step.allCases.count): \(Text(title))"))
        .accessibilityValue(isDone ? Text("Fatto") : isHighlighted ? Text("Prossimo") : Text("Da fare"))
    }
}
