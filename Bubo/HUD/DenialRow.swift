import SwiftUI

/// One action denied in an Esecuzione: the tool, the command or path, the level and the subagent if any; "Consenti
/// per questa Automazione" for levels 1–3 with a pattern `claude` proposed.
struct DenialRow: View {
    let denial: Denial
    /// Whether the Automazione already has every rule the denial proposes.
    let isAllowed: Bool
    /// Adds the denial's rules to the Automazione; `nil` when it is gone.
    let allow: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Text(verbatim: denial.tool)
                    .font(Typography.mono(size: 11, weight: .medium))
                if let subject = denial.subject {
                    Text(verbatim: RepoActivations.escaped(subject))
                        .font(Typography.mono(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(Text(verbatim: RepoActivations.escaped(subject)))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                if denial.level.isDangerous {
                    Label {
                        Text(denial.level.title)
                    } icon: {
                        Image(systemName: "exclamationmark.octagon")
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Palette.danger)
                } else {
                    Text(denial.level.title)
                        .foregroundStyle(Palette.textSecondary)
                }
                if let agent = denial.agent {
                    Text("Da \(agent)")
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .font(Typography.body(size: 11))
            .accessibilityElement(children: .combine)
            if denial.level.isDangerous {
                Text("Livello 4–5: fallo a mano riprendendo la Sessione.")
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            } else if denial.allowsRule {
                if isAllowed {
                    Text("Consentito in questa Automazione dalla prossima Esecuzione")
                        .font(Typography.body(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                } else if let allow {
                    Button("Consenti per questa Automazione", action: allow)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(Text(verbatim: denial.suggestions.joined(separator: ", ")))
                }
            }
        }
        .foregroundStyle(Palette.textPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: [denial.tool, denial.subject, String(localized: denial.level.title)]
            .compactMap(\.self).joined(separator: ", ")))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.small) {
        DenialRow(denial: Denial(BridgeDenial(id: "1", tool: "Bash", command: "npm test", suggestions: ["Bash(npm test)"],
                                              source: .sdk),
                                 classifier: RiskClassifier(workingDirectory: URL(filePath: "/tmp"))),
                  isAllowed: false) {}
        DenialRow(denial: Denial(BridgeDenial(id: "2", tool: "Bash", command: "git push --force", agent: "revisore",
                                              source: .gate),
                                 classifier: RiskClassifier(workingDirectory: URL(filePath: "/tmp"))),
                  isAllowed: false, allow: nil)
    }
    .frame(width: 320)
    .padding()
    .background(Palette.ink)
}
