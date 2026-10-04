import Foundation
import RemoteKit

/// A Richiesta di permesso waiting on a paired Mac.
struct WaitingRequest: Identifiable {
    /// The Mac that asks.
    let macID: UUID
    /// The Mac's name.
    let macName: String
    /// The Richiesta.
    let request: RemoteRequest

    var id: UUID { request.id }
}

/// Why a decision did not reach the Mac.
enum DecisionError: Error, Equatable {
    /// The Mac is no longer paired.
    case unknownMac
    /// The 10 minutes to decide from the iPhone are over.
    case expired
    /// Face ID was cancelled or changed: the Secure Enclave key did not sign.
    case notSigned
    /// The Verdict could not be written.
    case notSent

    /// What the iPhone says about it.
    var message: LocalizedStringResource {
        switch self {
        case .unknownMac: "Questo Mac non è più accoppiato."
        case .expired: "Scaduta: rispondi dal Mac."
        case .notSigned: "Decisione non firmata. Riprova; se hai cambiato Face ID, accoppia di nuovo questo iPhone."
        case .notSent: "Decisione non inviata. Controlla la connessione e riprova."
        }
    }
}
