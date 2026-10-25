import SwiftUI

/// The Suggeritore's window: the Orb that hears, the answers newest first, the trascrizione of the last two minutes of
/// the meeting Wispr Flow records and a field to ask in writing.
struct PromptView: View {
    let prompter: MeetingPrompter
    /// Opens a cited note, in Obsidian or in Quick Look.
    let openNote: (URL) -> OpenURLAction.Result
    let close: () -> Void
    @State private var typed = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.line)
            if !prompter.cards.isEmpty {
                ScrollView {
                    VStack(spacing: Spacing.xs) {
                        ForEach(prompter.cards) { card in
                            PromptCardView(card: card)
                                .chatEntrance()
                        }
                    }
                    .padding(Spacing.s)
                    .animation(Motion.isReduced ? nil : .easeOut(duration: 0.2), value: prompter.cards.map(\.id))
                }
                .frame(maxHeight: .infinity)
                Divider().overlay(Palette.line)
            }
            transcript
            composer
        }
        .frame(width: Self.width, height: Self.height)
        .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.panel))
        .environment(\.openURL, OpenURLAction(handler: openNote))
    }

    private var header: some View {
        HStack(spacing: Spacing.s) {
            HUDOrb(controls: prompter.orb)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Suggeritore")
                    .font(.buboInterface.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                statusText
                    .font(.buboData)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Rispondi all'ultima domanda", systemImage: "text.bubble") { prompter.answerLastQuestion() }
                .help("Rispondi all'ultima domanda sentita nell'ultimo minuto")
                .disabled(prompter.transcript.isEmpty)
            Button("Chiudi", systemImage: "xmark", action: close)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }

    private var statusText: Text {
        switch prompter.status {
        case .waiting: Text("Avvia la registrazione in Wispr Flow")
        case .listening: Text("In ascolto della riunione in Wispr Flow")
        case let .failed(failure): Text(failure.explanation)
        }
    }

    private var transcript: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    if prompter.transcript.isEmpty {
                        Text(prompter.status == .listening ? "Le frasi della riunione compaiono qui." : "Nessuna frase sentita.")
                            .font(.buboInterface)
                            .foregroundStyle(Palette.textFaint)
                    }
                    ForEach(Array(prompter.transcript.enumerated()), id: \.offset) { offset, line in
                        PromptLineView(line: line)
                            .id(offset)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
            }
            .frame(height: prompter.cards.isEmpty ? nil : Self.transcriptHeight)
            .frame(maxHeight: prompter.cards.isEmpty ? .infinity : nil)
            .onChange(of: prompter.transcript.count) { _, count in
                reader.scrollTo(count - 1, anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        TextField("Chiedi alle note…", text: $typed)
            .textFieldStyle(.plain)
            .font(.buboInterface)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .overlay(Capsule().strokeBorder(Palette.line))
            .onSubmit {
                prompter.answer(typed: typed)
                typed = ""
            }
            .padding(Spacing.s)
    }

    /// The size of the window.
    static let width: CGFloat = 400
    static let height: CGFloat = 600
    /// The height of the trascrizione under the answers.
    private static let transcriptHeight: CGFloat = 160
}
