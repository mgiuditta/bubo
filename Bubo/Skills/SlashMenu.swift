import SwiftUI

/// The skills that match the `/` typed in a prompt (#689): name and description on one line each, the chosen one
/// highlighted. Clicking a skill picks it; the keys stay with the prompt, which keeps the focus.
struct SlashMenu: View {
    let skills: [Skill]
    let selection: Skill.ID?
    let pick: (Skill) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(skills) { skill in
                Button {
                    pick(skill)
                } label: {
                    row(for: skill)
                }
                .buttonStyle(.plain)
                // The prompt keeps the keyboard: ↑↓, Tab and Invio choose from there.
                .focusable(false)
                .accessibilityLabel(Text(verbatim: skill.summary.isEmpty ? "/\(skill.name)" : "/\(skill.name), \(skill.summary)"))
                .accessibilityAddTraits(skill.id == selection ? .isSelected : [])
            }
        }
        .padding(Spacing.xxSmall)
        .background(Palette.ink, in: .rect(cornerRadius: CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.medium).strokeBorder(Palette.line)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Skill")
        .accessibilityIdentifier("slash.menu")
    }

    private func row(for skill: Skill) -> some View {
        HStack(spacing: Spacing.xSmall) {
            Text(verbatim: "/\(skill.name)")
                .font(Typography.body(size: 13, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .layoutPriority(1)
            Text(verbatim: skill.summary)
                .font(Typography.body(size: 12))
                .foregroundStyle(Palette.textSecondary)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, Spacing.xSmall)
        .padding(.vertical, Spacing.xxSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(skill.id == selection ? Palette.lineStrong : .clear, in: .rect(cornerRadius: CornerRadius.small))
        .contentShape(.rect)
    }
}
