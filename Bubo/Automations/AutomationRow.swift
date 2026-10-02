import SwiftUI

/// One Automazione of its window: name, Progetto, model, latest Esecuzione and [Avvia ora].
struct AutomationRow: View {
    let automation: Automation
    /// [Avvia ora].
    let run: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(verbatim: automation.name)
                    .font(Typography.body(size: 13, weight: .semibold))
                Text(verbatim: [automation.project.lastPathComponent, modelName].joined(separator: " · "))
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .help(automation.project.path)
                if let execution = automation.lastExecution {
                    Text("Ultima Esecuzione: \(execution.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(execution.denialCount) negate")
                        .font(Typography.body(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Avvia ora", action: run)
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, Spacing.xxSmall)
    }

    private var modelName: String {
        switch automation.model {
        case .router: String(localized: "Router")
        case let .fixed(alias): alias
        }
    }
}

#Preview {
    AutomationRow(automation: Automation(id: UUID(), name: "Test notturni", project: URL(filePath: "/tmp/bubo"),
                                         request: "Lancia i test")) {}
        .padding()
        .background(Palette.ink)
}
