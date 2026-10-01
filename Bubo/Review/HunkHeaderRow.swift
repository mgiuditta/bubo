import SwiftUI

/// The header of a blocco in the continuous diff: its place, why the agent wrote it, `+n −m`, Accetta and Rifiuta;
/// under it, the note to the agent, or the field to write it.
struct HunkHeaderRow: View {
    let file: ChangedFile
    let hunk: Hunk
    /// The blocco's place among all of them, from 1.
    let position: Int
    let count: Int
    /// Why the agent wrote the blocco; `nil` when it did not say.
    let reason: String?
    let decision: HunkDecision?
    /// Whether the keyboard acts on the blocco.
    let isCurrent: Bool
    let isNoting: Bool
    /// Whether the row has Accetta and Rifiuta: Focus has larger ones under the blocco.
    var showsButtons = true
    @Binding var note: String
    let decide: (HunkDecision) -> Void
    let saveNote: () -> Void
    let cancelNote: () -> Void
    @FocusState private var isNoteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Text(verbatim: "\(position)/\(count)")
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
                Text(verbatim: reason ?? fallback)
                    .font(Typography.body(size: 12, weight: reason == nil ? .regular : .medium))
                    .foregroundStyle(reason == nil ? Palette.textSecondary : Palette.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(reason ?? hunk.header)
                Text(verbatim: "+\(hunk.added) −\(hunk.removed)")
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
                Text(state)
                    .font(Typography.mono(size: 10, weight: .medium))
                    .foregroundStyle(stateColor)
                if showsButtons {
                    Button("Accetta") { decide(.accepted) }
                    Button("Rifiuta") { decide(.rejected(note: nil)) }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.xSmall)
            if isNoting {
                TextField("Nota per l'agente", text: $note, prompt: Text("Nota per l'agente, Invio per salvare"))
                    .textFieldStyle(.plain)
                    .font(Typography.body(size: 12))
                    .focused($isNoteFocused)
                    .onSubmit(saveNote)
                    .onExitCommand(perform: cancelNote)
                    .onAppear { isNoteFocused = true }
                    .padding(.horizontal, Spacing.small)
                    .padding(.bottom, Spacing.xSmall)
            } else if case let .rejected(note?) = decision {
                Text("↳ all'agente: \(note)")
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.attention)
                    .padding(.horizontal, Spacing.small)
                    .padding(.bottom, Spacing.xSmall)
            }
        }
        .background(Palette.surface, in: .rect(cornerRadius: CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .strokeBorder(isCurrent ? Palette.lineStrong : Palette.line, lineWidth: isCurrent ? 2 : 1)
        }
        .padding(.top, Spacing.xxSmall)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Blocco \(position) di \(count), \(file.path)"))
    }

    /// What the header says without a perché: what git says of a change without lines, or its `@@` line.
    private var fallback: String {
        if !hunk.lines.isEmpty { return hunk.header }
        if file.isBinary { return String(localized: "File binario") }
        if let oldPath = file.oldPath { return String(localized: "Rinominato da \(oldPath)") }
        return String(localized: "Nessuna riga da mostrare")
    }

    private var state: LocalizedStringKey {
        switch decision {
        case .accepted: "Accettato"
        case .rejected: "Rifiutato"
        case nil: "Da decidere"
        }
    }

    private var stateColor: Color {
        switch decision {
        case .accepted: Palette.success
        case .rejected: Palette.danger
        case nil: Palette.textFaint
        }
    }
}
