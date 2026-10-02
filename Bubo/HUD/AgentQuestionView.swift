import SwiftUI

/// The agent's questions inside their Sessione: each with its options, one or many to choose, and a written answer.
///
/// Rispondi sends the answers once every question has one; Non rispondere lets the agent go on without. With the
/// keyboard, ↩ answers and esc does not.
struct AgentQuestionView: View {
    let question: AgentQuestion
    /// Whether ↩ and esc answer it: only when no Richiesta di permesso holds the keyboard, so one key never answers two.
    let hasKeyboard: Bool
    /// Sends the replies, one per question in order; `nil` for Non rispondere.
    let answer: ([AgentQuestion.Reply]?) -> Void
    @State private var replies: [AgentQuestion.Reply]

    init(question: AgentQuestion, hasKeyboard: Bool, answer: @escaping ([AgentQuestion.Reply]?) -> Void) {
        self.question = question
        self.hasKeyboard = hasKeyboard
        self.answer = answer
        _replies = State(initialValue: Array(repeating: AgentQuestion.Reply(), count: question.items.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(question.items.count == 1 ? "Domanda dell'agente" : "Domande dell'agente")
                .font(Typography.mono(size: 10, weight: .medium))
                .textCase(.uppercase)
                .foregroundStyle(Palette.attention)
            ForEach(question.items.indices, id: \.self) { index in
                AgentQuestionItemView(item: question.items[index], reply: $replies[index])
            }
            HStack(spacing: Spacing.xSmall) {
                Button("Non rispondere") { answer(nil) }
                    .keyboardShortcut(hasKeyboard ? .cancelAction : nil)
                Button("Rispondi") { answer(replies) }
                    .keyboardShortcut(hasKeyboard ? .defaultAction : nil)
                    .disabled(!question.isAnswered(by: replies))
                Spacer(minLength: 0)
                if hasKeyboard {
                    Text("↩ Rispondi · esc Non rispondere")
                        .font(Typography.mono(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, Spacing.xxSmall)
        }
        .padding(Spacing.xSmall)
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .stroke(Palette.attention.opacity(0.5), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(question.items.count == 1 ? "Domanda dell'agente" : "Domande dell'agente")
    }
}

/// One of the agent's questions: its tag, the question, the options as buttons that show their choice, and a field
/// for a written answer. Choosing an option of a single-choice question clears what was written, and the other way.
private struct AgentQuestionItemView: View {
    let item: AgentQuestion.Item
    @Binding var reply: AgentQuestion.Reply

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            if !item.header.isEmpty {
                Text(verbatim: item.header)
                    .font(Typography.mono(size: 10, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
            }
            Text(verbatim: item.question)
                .font(Typography.body(size: 12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if item.allowsMultiple {
                Text("Puoi sceglierne più di una.")
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(item.options.indices, id: \.self) { index in
                optionButton(index)
            }
            TextField("Altra risposta", text: $reply.text, axis: .vertical)
                .font(Typography.body(size: 12))
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .onChange(of: reply.text) { _, text in
                    if !item.allowsMultiple, !text.isEmpty { reply.options = [] }
                }
        }
    }

    private func optionButton(_ index: Int) -> some View {
        let option = item.options[index]
        let isChosen = reply.options.contains(index)
        return Button {
            choose(index)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Image(systemName: symbol(isChosen: isChosen))
                    .foregroundStyle(isChosen ? Palette.attention : Palette.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: option.label)
                        .font(Typography.body(size: 12, weight: .medium))
                    if let detail = option.detail, !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(Typography.body(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: option.label))
        .accessibilityHint(option.detail.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func symbol(isChosen: Bool) -> String {
        switch (item.allowsMultiple, isChosen) {
        case (true, true): "checkmark.square.fill"
        case (true, false): "square"
        case (false, true): "largecircle.fill.circle"
        case (false, false): "circle"
        }
    }

    private func choose(_ index: Int) {
        if item.allowsMultiple {
            if let position = reply.options.firstIndex(of: index) {
                reply.options.remove(at: position)
            } else {
                reply.options.append(index)
                reply.options.sort()
            }
        } else {
            reply.options = [index]
            reply.text = ""
        }
    }
}

#Preview {
    AgentQuestionView(question: AgentQuestion(id: "q1", items: [
        .init(question: "Quale libreria uso per le date?", header: "Libreria",
              options: [.init(label: "date-fns", detail: "Leggera, funzioni pure"),
                        .init(label: "Luxon", detail: "Fusi orari completi")],
              allowsMultiple: false),
        .init(question: "Cosa abilito?", header: "Funzioni",
              options: [.init(label: "Cache"), .init(label: "Log"), .init(label: "Metriche")],
              allowsMultiple: true),
    ]), hasKeyboard: true) { _ in }
    .frame(width: 320)
    .padding()
    .background(Palette.ink)
}
