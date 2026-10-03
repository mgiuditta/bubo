import SwiftUI

/// The engine and model a new Sessione starts on, in ⌘N and in the Bozza (ADR 0012), with «Usa sempre per questo
/// Progetto», which makes them the Progetto's own for the next Sessioni.
struct EngineChoiceField: View {
    @Binding var choice: EngineChoice
    @Binding var isProjectDefault: Bool
    /// What `listModels()` listed; `nil` while it is read, empty without a Copilot that can answer.
    let copilotModels: [CopilotModel]?
    var settings = EndpointSettings.shared
    @State private var isAskingConsent = false

    var body: some View {
        LabeledContent("Motore e modello") {
            Menu {
                EngineChoiceItems(choice: choice, copilotModels: copilotModels,
                                  askCopilotConsent: settings.allowsCopilot ? nil : { isAskingConsent = true }) {
                    choice = $0
                }
            } label: {
                Text(verbatim: choice.name)
            }
            .fixedSize()
            .copilotConsentDialog(isPresented: $isAskingConsent, settings: settings)
        }
        Toggle("Usa sempre per questo Progetto", isOn: $isProjectDefault)
            .tint(Palette.switchTrack)
    }
}
