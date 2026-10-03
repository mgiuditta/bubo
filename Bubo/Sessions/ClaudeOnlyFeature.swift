import Foundation

/// A part of Bubo that exists only with Claude: a Sessione on Copilot says it is not available (ADR 0012).
enum ClaudeOnlyFeature: CaseIterable, Identifiable {
    case quota, projectMemory, plugins, agents, sandbox

    var id: Self { self }

    /// The part's name.
    var title: LocalizedStringResource {
        switch self {
        case .quota: "Quota"
        case .projectMemory: "Memoria di Progetto"
        case .plugins: "Plugin"
        case .agents: "Agenti"
        case .sandbox: "Sandbox"
        }
    }

    /// Why a Sessione on Copilot does without it, in one line.
    var explanation: LocalizedStringResource {
        switch self {
        case .quota: "La Quota è dell'abbonamento Claude. Qui conta la Spesa stimata, in crediti."
        case .projectMemory: "Copilot non legge né scrive la Memoria di Progetto."
        case .plugins: "I Plugin installati valgono solo per Claude. Copilot non li carica."
        case .agents: "Gli Agenti funzionano solo con Claude."
        case .sandbox: "I comandi di Copilot girano con i tuoi permessi, senza Sandbox."
        }
    }
}
