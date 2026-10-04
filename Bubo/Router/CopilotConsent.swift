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

    /// The id among ``consents`` of the consent for the notes of the Secondo cervello to Copilot (#678); no endpoint
    /// has it.
    nonisolated static let copilotNotesConsentID = "github-copilot-notes"

    /// Whether the user allowed Copilot to receive the Profilo, the Regole and the notes `cerca` finds, and to write
    /// with `ricorda`, in a Domanda.
    var allowsCopilotNotes: Bool { consents.contains(Self.copilotNotesConsentID) }

    /// Whether a Domanda for Copilot must first ask the consent for the notes: there is a Secondo cervello, Copilot
    /// may receive Domande, and the user was never asked.
    func needsCopilotNotesConsent(hasSecondBrain: Bool) -> Bool {
        hasSecondBrain && allowsCopilot && !allowsCopilotNotes && !hasAskedCopilotNotesConsent
    }

    /// Answers the question asked once: allowed, the notes go to Copilot from now on; otherwise they never do, and
    /// Bubo does not ask again. Either way it can be changed in Impostazioni › Modelli.
    func answerCopilotNotesConsent(allowing isAllowed: Bool) {
        markCopilotNotesConsentAsked()
        if isAllowed { grantConsent(toProvider: Self.copilotNotesConsentID) }
    }

    /// Takes back the consent for the notes: the Domande for Copilot go as before, without them.
    func revokeCopilotNotesConsent() {
        revokeConsent(ofProvider: Self.copilotNotesConsentID)
    }
}
