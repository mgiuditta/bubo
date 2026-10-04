import SwiftUI

/// The Automazioni window, from the Finestra menu: each Automazione with its Progetto, model, Ripetizione and latest
/// Esecuzione, [Avvia ora], Pausa/Riprendi, Modifica, Elimina, and Nuova Automazione (spec 19).
struct AutomationsWindow: View {
    /// The id of the window's scene.
    static let windowID = "automazioni"

    /// The Sessioni, with the Automazioni; `nil` when they are unavailable.
    let store: SessionStore?
    /// What starts the Esecuzioni; `nil` when the Sessioni are unavailable.
    let runner: ExecutionRunner?
    /// Brings the HUD to the front on a Sessione: Apri Sessione of the Storico.
    var showSession: (UUID) -> Void = { _ in }
    @State private var isCreating = false
    /// The Automazione whose Modifica sheet is open.
    @State private var editing: Automation?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack {
                Spacer()
                Button("Nuova Automazione", systemImage: "plus") { isCreating = true }
                    .disabled(store == nil)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Spacing.medium)
        .frame(minWidth: 520, idealWidth: 640, minHeight: 360, idealHeight: 520)
        .font(Typography.body(size: 13))
        .foregroundStyle(Palette.textPrimary)
        // The Notte direction's graphite, under the title bar too, like the Agenti window (ADR 0004).
        .containerBackground(Palette.ink, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isCreating) {
            if let store {
                AutomationSheet(projects: store.projects) { store.automations.add($0) }
            }
        }
        .sheet(item: $editing) { automation in
            if let store {
                AutomationSheet(projects: store.projects, editing: automation) { store.automations.update($0) }
            }
        }
        // Last, so the sheet gets it too: selection is lightness, not the system blue (design system).
        .tint(Palette.accent)
    }

    @ViewBuilder
    private var content: some View {
        if let store, !store.automations.automations.isEmpty {
            List {
                ReadinessCard()
                    .listRowSeparator(.hidden)
                ForEach(store.automations.automations) { automation in
                    AutomationRow(automation: automation, resume: resumeAction(for: automation, in: store),
                                  openSession: { openAction(for: $0, in: store) }) {
                        runner?.run(automation.id)
                    } togglePause: {
                        if automation.isPaused {
                            store.automations.resume(automation.id)
                        } else {
                            store.automations.pause(automation.id)
                        }
                    } edit: {
                        editing = automation
                    } delete: {
                        store.automations.remove(automation.id)
                    }
                    .listRowSeparatorTint(Palette.line)
                }
            }
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView {
                Label("Nessuna Automazione", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Una richiesta che parte da sola all'ora che scegli, come nuova Sessione su un Progetto.")
            } actions: {
                Button("Nuova Automazione") { isCreating = true }
            }
        }
    }

    /// Apri Sessione of an Esecuzione whose Sessione `id` is still in the Vista; `nil` once it is gone or archived,
    /// as the Senza modifiche.
    private func openAction(for id: UUID, in store: SessionStore) -> (() -> Void)? {
        guard store.sessions.contains(where: { $0.id == id && $0.isLive }) else { return nil }
        return { showSession(id) }
    }

    /// Riprendi of the latest Esecuzione of `automation`, when the Mac's sleep or Bubo's quitting interrupted it and its
    /// Sessione still waits: the agent's Conversazione resumes there.
    private func resumeAction(for automation: Automation, in store: SessionStore) -> (() -> Void)? {
        guard let execution = automation.lastExecution, execution.outcome == .interrotta,
              let id = execution.session,
              let session = store.sessions.first(where: { $0.id == id }),
              session.isInterrupted, session.activity == .ferma
        else { return nil }
        return { store.resume(id) }
    }
}

#Preview {
    AutomationsWindow(store: nil, runner: nil)
}
