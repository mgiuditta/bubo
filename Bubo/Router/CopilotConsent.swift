import Foundation

/// GitHub Copilot as a cloud provider with its own consent (spec 10, ADR 0011, ADR 0012).
///
/// Without it nothing goes to Copilot: neither a Domanda nor a turn of a Sessione, which carries the files of the
/// Progetto. The consent lives with the endpoints' ones, in ``EndpointSettings/consents``.
extension EndpointSettings {
    /// The id of Copilot's consent among ``consents``; no endpoint has it.
    nonisolated static let copilotConsentID = "github-copilot"

    /// The page of the user's Copilot settings on GitHub, whose Privacy section holds "Allow GitHub to use my data for
    /// AI model training": on by default on the individual plans since 2026-04-24.
    nonisolated static let copilotTrainingSettingsURL = URL(string: "https://github.com/settings/copilot/features")!

    /// Whether the user allowed Copilot to receive the contenuti del Progetto.
    var allowsCopilot: Bool { consents.contains(Self.copilotConsentID) }

    /// Allows Copilot to receive Domande and the turns of the Sessioni from now on; the user gave it, never Bubo.
    func grantCopilotConsent() {
        grantConsent(toProvider: Self.copilotConsentID)
    }

    /// Takes back Copilot's consent: it receives nothing more until the user allows it again.
    func revokeCopilotConsent() {
        revokeConsent(ofProvider: Self.copilotConsentID)
    }
}
