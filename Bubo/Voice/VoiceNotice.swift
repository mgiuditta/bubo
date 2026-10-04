import SwiftUI

/// The line under the prompt when push-to-talk could not listen, with the way out.
struct VoiceNotice: View {
    let failure: VoiceFailure
    /// Hides the line.
    let dismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch failure {
        case .microphoneDenied:
            ErrorNotice("Bubo non può usare il microfono",
                        remedy: "Consentilo in Impostazioni di Sistema › Privacy e sicurezza › Microfono.",
                        actionTitle: "Apri Impostazioni") { openURL(MicrophoneAccess.settingsURL) }
        case .microphoneUnavailable:
            ErrorNotice("Microfono non disponibile",
                        remedy: "Collega un microfono o scegline uno in Impostazioni di Sistema › Suono.",
                        actionTitle: "Apri Impostazioni") { openURL(Self.soundSettingsURL) }
        case .languageUnsupported:
            ErrorNotice("La dettatura non conosce la lingua del Mac",
                        remedy: "Scegli italiano o inglese in Impostazioni di Sistema › Generali › Lingua e Zona.",
                        actionTitle: "Apri Impostazioni") { openURL(Self.languageSettingsURL) }
        case .modelDownloading:
            ErrorNotice("Sto scaricando il modello della dettatura",
                        remedy: "Serve una volta sola: riprova tra poco.", actionTitle: "Chiudi", action: dismiss)
        case .modelUnavailable:
            ErrorNotice("Manca il modello della dettatura",
                        remedy: "Collegati a Internet e riprova: si scarica una volta sola, poi funziona offline.",
                        actionTitle: "Chiudi", action: dismiss)
        case .nothingHeard:
            ErrorNotice("Non ho sentito niente",
                        remedy: "Tieni premuta la scorciatoia mentre parli, poi rilascia.",
                        actionTitle: "Chiudi", action: dismiss)
        }
    }

    private static let soundSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!
    private static let languageSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!
}
