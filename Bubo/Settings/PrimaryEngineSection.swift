import SwiftUI

/// The Motore principale in Impostazioni › Modelli (ADR 0014): the Motore Domande and Sessioni start on, and, when
/// both `claude` and `copilot` can answer, whether the other one is the Riserva.
struct PrimaryEngineSection: View {
    let settings: EndpointSettings
    /// Asks the user's `claude` whether it can answer.
    var detectClaude: @Sendable () async -> ClaudeReadiness = { await ClaudeReadiness.detect() }
    /// Asks the user's `copilot` whether it can answer.
    var detectCopilot: @Sendable () async -> CopilotReadiness = { await CopilotReadiness.detect() }
    @AppStorage(PrimaryEngine.engineKey) private var engine = PrimaryEngine().engine
    @AppStorage(PrimaryEngine.reserveKey) private var hasReserve = PrimaryEngine().hasReserve
    @State private var isClaudeReady = false
    @State private var isCopilotReady = false

    var body: some View {
        Section {
            Picker("Motore principale", selection: $engine) {
                Text(verbatim: "Claude").tag(Session.Engine.claude)
                Text(verbatim: "Copilot").tag(Session.Engine.copilot)
                    // Copilot answers only with the user's consent.
                    .disabled(!settings.allowsCopilot)
            }
            if isClaudeReady, isCopilotReady {
                Toggle(engine == .claude ? LocalizedStringKey("Copilot di riserva") : "Claude di riserva", isOn: $hasReserve)
            }
        } header: {
            Text("Motore")
        } footer: {
            Text("Domande e Sessioni partono sul Motore principale, se non hai scelto un modello per il tipo di Domanda o per il Progetto. La riserva risponde solo quando il principale finisce la quota o raggiunge un limite.")
        }
        .task {
            async let claude = detectClaude()
            async let copilot = detectCopilot()
            if case .ready = await claude { isClaudeReady = true }
            if case .ready = await copilot { isCopilotReady = true }
        }
    }
}

#Preview {
    Form {
        PrimaryEngineSection(settings: .shared, detectClaude: { .ready(version: "2.1.0", method: "Max") },
                             detectCopilot: { .ready(version: "1.0.16", account: "octocat") })
    }
    .formStyle(.grouped)
}
