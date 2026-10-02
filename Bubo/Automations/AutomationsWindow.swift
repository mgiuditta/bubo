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
                ForEach(store.automations.automations) { automation in
                    AutomationRow(automation: automation) {
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
            ContentUnavailableView("Automazioni", systemImage: "clock.arrow.circlepath",
                                   description: Text("Nessuna Automazione. Creane una con Nuova Automazione."))
        }
    }
}

#Preview {
    AutomationsWindow(store: nil, runner: nil)
}
