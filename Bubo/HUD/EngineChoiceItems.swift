import SwiftUI

/// The items of a menu that chooses the engine and model of a Sessione's turns (ADR 0012): Claude with the steps of
/// its Scala, Copilot with the models of the user's plan. Without a Copilot that can answer, the Copilot item opens
/// Impostazioni › Modelli, where it is installed or signed in; without the user's consent, it asks for it first.
struct EngineChoiceItems: View {
    let choice: EngineChoice
    /// The engines offered: both before the Sessione starts, its own after.
    var engines: [Session.Engine] = [.claude, .copilot]
    /// What `listModels()` listed; `nil` while it is read, empty without a Copilot that can answer.
    let copilotModels: [CopilotModel]?
    /// Asks the user's consent to send the turns to Copilot (spec 10); `nil` where it was already given.
    var askCopilotConsent: (() -> Void)?
    let choose: (EngineChoice) -> Void

    @Environment(\.openSettings) private var openSettings

    /// The Claude steps offered: those below Fable, whose efforts the SDK lowers by itself where a model lacks them.
    private let scala = Scala(catalog: nil)

    var body: some View {
        if let stronger {
            Button("Più forte: \(stronger.name)") { choose(stronger) }
            Divider()
        }
        if engines.contains(.claude) {
            Section("Claude") {
                item(Text("Predefinito di Claude"), for: EngineChoice(engine: .claude))
                ForEach(scala.steps, id: \.self) { step in
                    item(Text(verbatim: step.name), for: EngineChoice(engine: .claude, claudeModel: step))
                }
            }
        }
        if engines.contains(.copilot) {
            Section("Copilot") {
                if let askCopilotConsent {
                    Button("Consenti Copilot…", action: askCopilotConsent)
                } else if let copilotModels, !copilotModels.isEmpty {
                    item(Text("Predefinito di Copilot"), for: EngineChoice(engine: .copilot))
                    ForEach(CopilotStep.scala(of: copilotModels), id: \.self) { step in
                        item(Text(verbatim: step.name), for: EngineChoice(engine: .copilot, copilotModel: step))
                    }
                } else if copilotModels == nil {
                    Text("Caricamento dei modelli…")
                } else {
                    Button("Collega Copilot…") {
                        SettingsTab.models.select()
                        openSettings()
                    }
                }
            }
        }
    }

    /// One step up the Scala of the engine chosen; `nil` at its top, or for the engine's own default.
    private var stronger: EngineChoice? {
        choice.stronger(copilotModels: copilotModels ?? [])
    }

    /// The menu item that chooses `item`, with a check on the one chosen now.
    @ViewBuilder
    private func item(_ title: Text, for item: EngineChoice) -> some View {
        Button {
            choose(item)
        } label: {
            if item == choice {
                Label { title } icon: { Image(systemName: "checkmark") }
            } else {
                title
            }
        }
    }
}
