import SwiftUI

/// The agent's questions inside their Sessione, drawn like `AskUserQuestion` in the command line: one question at a
/// time behind tabs of their tags, numbered options, «Altro» last for a written answer, and the chosen option's
/// preview beside the list.
///
/// A single single-choice question answers at the first click; otherwise a click on a single-choice option moves to
/// the next question, and Rispondi sends the answers once every question has one. Non rispondere lets the agent go on
/// without. With the keyboard, ↩ answers and esc does not.
struct AgentQuestionView: View {
    let question: AgentQuestion
    /// Whether ↩ and esc answer it: only when no Richiesta di permesso holds the keyboard, so one key never answers two.
    let hasKeyboard: Bool
    /// Sends the replies, one per question in order; `nil` for Non rispondere.
    let answer: ([AgentQuestion.Reply]?) -> Void
    @State private var replies: [AgentQuestion.Reply]
    /// The question on show.
    @State private var current = 0

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
            if question.items.count > 1 { tabs }
            AgentQuestionItemView(item: question.items[current], reply: $replies[current]) { choose(at: current) }
                .id(current)
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

    /// One tab per question, named by its tag, with a check once it has an answer.
    private var tabs: some View {
        HStack(spacing: Spacing.xxSmall) {
            ForEach(question.items.indices, id: \.self) { index in
                let item = question.items[index]
                let isAnswered = replies[index].answers(item)
                Button {
                    current = index
                } label: {
                    Label {
                        if item.header.isEmpty { Text("Domanda \(index + 1)") } else { Text(verbatim: item.header) }
                    } icon: {
                        Image(systemName: isAnswered ? "checkmark.square.fill" : "square")
                    }
                    .font(Typography.mono(size: 10, weight: .medium))
                    .padding(.horizontal, Spacing.xSmall)
                    .padding(.vertical, 3)
                    .foregroundStyle(index == current ? Palette.ink : Palette.textSecondary)
                    .background(index == current ? Palette.attention : Palette.surface, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == current ? .isSelected : [])
            }
        }
    }

    /// After a single-choice option: answers a lone question at once, otherwise moves to the next question.
    private func choose(at index: Int) {
        guard !question.items[index].allowsMultiple else { return }
        if question.items.count == 1 {
            answer(replies)
        } else if index + 1 < question.items.count {
            current = index + 1
        }
    }
}

/// One of the agent's questions: the question, its options numbered as in the command line, «Altro» last with a
/// field for a written answer, and the preview of the option under the pointer or chosen, when the agent gives one.
private struct AgentQuestionItemView: View {
    let item: AgentQuestion.Item
    @Binding var reply: AgentQuestion.Reply
    /// Called after a click on an option, not on «Altro».
    let chose: () -> Void
    /// Whether «Altro» is chosen, so the field shows.
    @State private var writesOther = false
    /// The option under the pointer, whose preview shows.
    @State private var hovered: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(verbatim: item.question)
                .font(Typography.body(size: 12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if item.allowsMultiple {
                Text("Puoi sceglierne più di una.")
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
            if let preview {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Spacing.xSmall) {
                        options.frame(minWidth: 200, maxWidth: 260)
                        previewBox(preview).frame(minWidth: 240)
                    }
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        options
                        previewBox(preview)
                    }
                }
            } else {
                options
            }
        }
        .onAppear { writesOther = !reply.text.isEmpty }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(item.options.indices, id: \.self) { index in
                let option = item.options[index]
                row(number: index + 1, label: option.label, detail: option.detail,
                    isChosen: reply.options.contains(index)) {
                    toggle(index)
                }
                .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
            }
            row(number: item.options.count + 1, label: String(localized: "Altro…"), detail: nil,
                isChosen: writesOther) {
                writesOther.toggle()
                if writesOther, !item.allowsMultiple { reply.options = [] }
                if !writesOther { reply.text = "" }
            }
            if writesOther {
                TextField("La tua risposta", text: $reply.text, axis: .vertical)
                    .font(Typography.body(size: 12))
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .padding(.leading, Spacing.medium)
            }
        }
    }

    /// The preview of the hovered option, else of the chosen one, else of the first that has one.
    private var preview: String? {
        let previews = item.options.map(\.preview)
        guard previews.contains(where: { $0?.isEmpty == false }) else { return nil }
        let index = hovered ?? reply.options.first ?? previews.firstIndex { $0?.isEmpty == false }
        return index.flatMap { previews[$0] } ?? ""
    }

    private func previewBox(_ text: String) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Text(verbatim: text)
                .font(Typography.mono(size: 11))
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize()
                .padding(Spacing.xSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 220)
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.small))
        .overlay { RoundedRectangle(cornerRadius: CornerRadius.small).stroke(Palette.line) }
        .accessibilityLabel(Text("Anteprima"))
    }

    private func row(number: Int, label: String, detail: String?, isChosen: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Text(verbatim: "\(number).")
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(isChosen ? Palette.attention : Palette.textSecondary)
                    .accessibilityHidden(true)
                if item.allowsMultiple {
                    Image(systemName: isChosen ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isChosen ? Palette.attention : Palette.textSecondary)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: label)
                        .font(Typography.body(size: 12, weight: .medium))
                        .foregroundStyle(isChosen ? Palette.textPrimary : Palette.textPrimary.opacity(0.85))
                    if let detail, !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(Typography.body(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.xxSmall)
            .padding(.vertical, 3)
            .background(isChosen ? Palette.rowSelection : .clear, in: .rect(cornerRadius: CornerRadius.small))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityHint(detail.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func toggle(_ index: Int) {
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
            writesOther = false
            chose()
        }
    }
}

#Preview {
    AgentQuestionView(question: AgentQuestion(id: "q1", items: [
        .init(question: "Quale layout uso?", header: "Layout",
              options: [.init(label: "Colonne", detail: "Due colonne affiancate", preview: "┌────┬────┐\n│ A  │ B  │\n└────┴────┘"),
                        .init(label: "Righe", detail: "Una sopra l'altra", preview: "┌─────────┐\n│    A    │\n├─────────┤\n│    B    │\n└─────────┘")],
              allowsMultiple: false),
        .init(question: "Cosa abilito?", header: "Funzioni",
              options: [.init(label: "Cache"), .init(label: "Log"), .init(label: "Metriche")],
              allowsMultiple: true),
    ]), hasKeyboard: true) { _ in }
    .frame(width: 560)
    .padding()
    .background(Palette.ink)
}
