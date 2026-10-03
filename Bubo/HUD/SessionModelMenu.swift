import SwiftUI

/// The model · sforzo of a Sessione's turns, in its menu: from the next turn, without restarting it (spec 10, Nella
/// Sessione). Only the models of the Sessione's engine: a turn on the other engine would not see the conversation.
/// "Più forte" climbs one step of that engine's Scala from the one chosen.
struct SessionModelMenu: View {
    let choice: EngineChoice
    /// What `listModels()` listed; `nil` while it is read, empty without a Copilot that can answer.
    let copilotModels: [CopilotModel]?
    let choose: (EngineChoice) -> Void

    var body: some View {
        Menu("Modello dal prossimo turno") {
            EngineChoiceItems(choice: choice, engines: [choice.engine], copilotModels: copilotModels, choose: choose)
        }
    }
}

#Preview {
    SessionModelMenu(choice: EngineChoice(engine: .claude, claudeModel: Scala.Step(family: .sonnet, effort: .medium)),
                     copilotModels: nil) { _ in }
        .padding()
        .background(Palette.ink)
}
