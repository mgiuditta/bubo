import SwiftUI

/// The home's invitation under the big Orb: «Chiedi al tuo cervello» and three suggestions that fill the prompt.
struct HomeHeader: View {
    @Bindable var questions: QuestionModel
    @Environment(SecondBrain.self) private var secondBrain
    @State private var suggestions = HomeSuggestions.make(recentNotes: [])
    @State private var isSettingUp = false

    var body: some View {
        VStack(spacing: Spacing.m) {
            Text("Chiedi al tuo cervello")
                .font(.buboDisplay)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Spacing.xs) {
                // Without a folder the suggestions («Cosa ricordi di me?») have no answer: the step that gives them one.
                if secondBrain.location == nil {
                    chip(Text("Scegli la cartella delle tue note…")) { isSettingUp = true }
                } else {
                    ForEach(suggestions, id: \.self) { suggestion in
                        chip(Text(verbatim: suggestion)) { questions.prompt = suggestion }
                    }
                }
            }
        }
        .sheet(isPresented: $isSettingUp) { SecondBrainSetupSheet(steps: [.folder]) }
        .task(id: secondBrain.location?.path) {
            guard let folder = secondBrain.location?.url else { return }
            suggestions = HomeSuggestions.make(recentNotes: await HomeSuggestions.recentNotes(in: folder))
        }
    }

    private func chip(_ title: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) { title }
            .buttonStyle(.plain)
            .font(.buboInterface)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .overlay(Capsule().strokeBorder(Palette.line))
            .contentShape(.capsule)
    }
}
