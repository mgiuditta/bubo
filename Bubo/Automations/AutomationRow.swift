import SwiftUI

/// One Automazione of its window: name, Progetto, model, Ripetizione with its next time or its pausa, latest
/// Esecuzione, [Avvia ora] and Pausa/Riprendi, Modifica and Elimina; its Storico folded under it.
struct AutomationRow: View {
    let automation: Automation
    /// Riprendi of its latest Esecuzione, Interrotta; `nil` when there is none to resume.
    var resume: (() -> Void)?
    /// Opens the HUD on the Sessione of one of its Esecuzioni; `nil` when that Sessione is gone or archived.
    var openSession: (UUID) -> (() -> Void)? = { _ in nil }
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
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            summary
            if !automation.executions.isEmpty {
                ExecutionHistory(executions: automation.executions, openSession: openSession)
            }
        }
        .padding(.vertical, Spacing.xxSmall)
        .confirmationDialog("Eliminare «\(automation.name)»?", isPresented: $isConfirmingDelete) {
            Button("Elimina", role: .destructive, action: delete)
        } message: {
            Text("Le Sessioni già nate restano. Le Regole «in questa Automazione» se ne vanno con lei.")
        }
    }

    /// Name, Progetto, model, Ripetizione and latest Esecuzione, with the buttons.
    private var summary: some View {
        HStack(alignment: .center, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(verbatim: automation.name)
                    .font(Typography.body(size: 13, weight: .semibold))
                Text(verbatim: details)
                    .font(Typography.mono(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .help(automation.project.path)
                Text(verbatim: schedule)
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                if let pause = pauseNotice {
                    Label(pause, systemImage: "exclamationmark.triangle")
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
            if let resume {
                Button("Riprendi", action: resume)
                    .help("Riprende la Sessione dell'Esecuzione interrotta")
            }
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
    }

    /// The Ripetizione with the next time, or why nothing starts by itself.
    private var schedule: String {
        guard let recurrence = automation.recurrence else { return String(localized: "Solo con Avvia ora") }
        if automation.isPaused { return String(localized: "\(recurrence.title()) · in pausa") }
        guard let next = automation.nextDate(after: .now) else { return recurrence.title() }
        return String(localized: "\(recurrence.title()) · prossima \(next.formatted(date: .abbreviated, time: .shortened))")
    }

    /// Why Bubo put it in pausa by itself, and what brings it back; `nil` when it did not.
    private var pauseNotice: String? {
        switch automation.pauseReason {
        case .projectMissing:
            String(localized: "In pausa: il Progetto non è più in \(automation.project.path). Riportalo lì, poi Riprendi.")
        case .agentMissing:
            String(localized: "In pausa: l'agente «\(automation.agent ?? "")» non c'è più. Ripristina il file o scegli un altro agente in Modifica, poi Riprendi.")
        case nil:
            nil
        }
    }

    /// Progetto, model and agent, the line under the name.
    private var details: String {
        [automation.project.lastPathComponent, modelName, automation.agent].compactMap(\.self).joined(separator: " · ")
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
