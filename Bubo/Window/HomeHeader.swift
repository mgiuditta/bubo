import SwiftUI

/// The home's invitation under the big Orb: «Chiedi al tuo cervello» and three suggestions that fill the prompt.
struct HomeHeader: View {
    @Bindable var questions: QuestionModel
    @Environment(SecondBrain.self) private var secondBrain
    @State private var suggestions = HomeSuggestions.make(recentNotes: [])

    var body: some View {
        VStack(spacing: Spacing.m) {
            Text("Chiedi al tuo cervello")
                .font(.buboDisplay)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Spacing.xs) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { questions.prompt = suggestion }
                        .buttonStyle(.plain)
                        .font(.buboInterface)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.s)
                        .padding(.vertical, Spacing.xxs)
                        .overlay(Capsule().strokeBorder(Palette.line))
                        .contentShape(.capsule)
                }
            }
        }
        .task(id: secondBrain.location?.path) {
            guard let folder = secondBrain.location?.url else { return }
            suggestions = HomeSuggestions.make(recentNotes: await HomeSuggestions.recentNotes(in: folder))
        }
    }
}
