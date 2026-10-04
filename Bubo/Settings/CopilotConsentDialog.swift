import SwiftUI

/// What Copilot does with what it receives: on the individual plans GitHub trains its models on it unless the user
/// turns it off on GitHub (ADR 0011).
struct CopilotTrainingNotice: View {
    var body: some View {
        Text("Sui piani Copilot individuali (Free, Pro, Pro+, Max) GitHub usa per default ciò che riceve per addestrare i suoi modelli. Puoi disattivarlo su GitHub, nelle impostazioni di Copilot, sezione Privacy.")
    }
}

extension View {
    /// Asks the user's consent before anything goes to Copilot, with the notice on training (spec 10).
    ///
    /// The consent is given only by the user's choice, in ``EndpointSettings``.
    /// - Parameters:
    ///   - isPresented: Whether the question is shown.
    ///   - settings: Where the consent is kept.
    func copilotConsentDialog(isPresented: Binding<Bool>, settings: EndpointSettings) -> some View {
        confirmationDialog("Mandare Domande e file dei Progetti a GitHub Copilot?", isPresented: isPresented) {
            Button("Consenti", action: settings.grantCopilotConsent)
            Button("Annulla", role: .cancel) {}
        } message: {
            CopilotTrainingNotice()
        }
    }
}
