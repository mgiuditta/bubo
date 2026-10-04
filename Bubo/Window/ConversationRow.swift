import SwiftUI

/// A row of the Conversazioni: the title; for a Sessione, its Progetto and, when it waits for the user, the Lume dot.
struct ConversationRow: View {
    let item: ConversationItem

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(item.title)
                .font(.buboInterface)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch item {
            case let .session(_, _, project, _, activity):
                if activity == .attende {
                    Circle()
                        .fill(Palette.attention)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                ProjectChip(name: project.lastPathComponent)
            case let .cli(_, _, project, _):
                if let project { ProjectChip(name: project.lastPathComponent) }
            case .question(let question):
                if question.sessionID != nil {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(Palette.textSecondary)
                        .help(Text("Diventata una Sessione"))
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(minHeight: Spacing.sidebarRowMinHeight)
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    /// What VoiceOver adds to the title: the Progetto and whether the Sessione waits for the user.
    private var accessibilityValue: String {
        switch item {
        case let .session(_, _, project, _, activity):
            let waiting = activity == .attende ? String(localized: "Attende te") : nil
            return [project.lastPathComponent, waiting].compactMap(\.self).joined(separator: ", ")
        case let .cli(_, _, project, _):
            return [String(localized: "Riga di comando"), project?.lastPathComponent].compactMap(\.self)
                .joined(separator: ", ")
        case .question(let question):
            return question.sessionID == nil ? "" : String(localized: "Diventata una Sessione")
        }
    }
}

/// The name of a Progetto in a capsule with a thin line, beside a conversation.
struct ProjectChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.buboData)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs / 2)
            .overlay(Capsule().strokeBorder(Palette.line))
    }
}
