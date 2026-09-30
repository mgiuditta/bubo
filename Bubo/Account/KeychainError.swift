import Foundation
import Security

/// A keychain call that failed, with its `OSStatus`. Never carries the secret.
struct KeychainError: LocalizedError, Equatable {
    /// The status returned by the `SecItem` call.
    let status: OSStatus

    var errorDescription: String? {
        switch status {
        case errSecInteractionNotAllowed:
            String(localized: "Il Portachiavi è bloccato: sblocca il Mac e riprova.")
        default:
            String(localized: "Errore del Portachiavi (\(status)).")
        }
    }
}
