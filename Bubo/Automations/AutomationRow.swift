import SwiftUI

/// One Automazione of its window: name, Progetto, model, Ripetizione with its next time or its pausa, latest
/// Esecuzione, [Avvia ora] and Pausa/Riprendi, Modifica and Elimina.
struct AutomationRow: View {
    let automation: Automation
    /// [Avvia ora].
    let run: () -> Void
    /// Pausa, or Riprendi when in pausa.
    let togglePause: () -> Void
    /// Modifica…: opens the sheet on it.
    let edit: () -> Void
    /// Elimina, once confirmed.
    let delete: () -> Void
    @State private var isConfirmingDelete = false

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(verbatim: automation.name)
                    .font(Typography.body(size: 13, weight: .semibold))
                Text(verbatim: [automation.project.lastPathComponent, modelName].joined(separator: " · "))
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .help(automation.project.path)
                Text(verbatim: schedule)
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                if automation.pauseReason == .projectMissing {
                    Label("In pausa: il Progetto non è più in \(automation.project.path). Riportalo lì, poi Riprendi.",
                          systemImage: "exclamationmark.triangle")
                        .font(Typography.body(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let execution = automation.lastExecution {
                    Text("Ultima Esecuzione: \(execution.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(execution.title) · \(execution.denialCount) negate")
                        .font(Typography.body(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Avvia ora", action: run)
                .buttonStyle(.borderedProminent)
            Menu("Azioni", systemImage: "ellipsis.circle") {
                Button(automation.isPaused ? "Riprendi" : "Pausa", action: togglePause)
                Button("Modifica…", action: edit)
                Divider()
                Button("Elimina…", role: .destructive) { isConfirmingDelete = true }
            }
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, Spacing.xxSmall)
        .confirmationDialog("Eliminare «\(automation.name)»?", isPresented: $isConfirmingDelete) {
            Button("Elimina", role: .destructive, action: delete)
        } message: {
            Text("Le Sessioni già nate restano. Le Regole «in questa Automazione» se ne vanno con lei.")
        }
    }

    /// The Ripetizione with the next time, or why nothing starts by itself.
    private var schedule: String {
        guard let recurrence = automation.recurrence else { return String(localized: "Solo con Avvia ora") }
        if automation.isPaused { return String(localized: "\(recurrence.title()) · in pausa") }
        guard let next = automation.nextDate(after: .now) else { return recurrence.title() }
        return String(localized: "\(recurrence.title()) · prossima \(next.formatted(date: .abbreviated, time: .shortened))")
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
                                         request: "Lancia i test", recurrence: .weekdays(hour: 9, minute: 0)),
                  run: {}, togglePause: {}, edit: {}, delete: {})
        .padding()
        .background(Palette.ink)
}
