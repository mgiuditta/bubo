import Foundation
import os

/// The OpenAI-compatible endpoints the user set up, and the clouds among them allowed to receive Domande.
///
/// Kept in the user defaults: addresses, model ids and consents, never a key (those stay in the keychain).
@Observable
final class EndpointSettings {
    /// The one shared by the HUD and the settings window.
    static let shared = EndpointSettings()

    /// The known endpoints first, then the custom ones in the order they were added.
    private(set) var endpoints: [OpenAICompatibleEndpoint]
    /// The ids of the clouds that are not Claude the user allowed to receive Domande, and Copilot's
    /// (``copilotConsentID``) for the contenuti del Progetto too; revocable.
    private(set) var consents: Set<String>
    /// The id of the Modello locale's endpoint, a server on the Mac; `nil` without one.
    private(set) var localModelID: String?
    /// Whether Bubo already proposed a Modello locale: it does so once, whatever the answer.
    private(set) var hasOfferedLocalModel: Bool

    /// Creates the settings saved in `defaults`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var saved: [OpenAICompatibleEndpoint] = []
        if let data = defaults.data(forKey: Self.endpointsKey) {
            do {
                saved = try JSONDecoder().decode([OpenAICompatibleEndpoint].self, from: data)
            } catch {
                Logger(subsystem: "com.mgiuditta.bubo", category: "router")
                    .error("Endpoints unreadable, back to the known ones: \(String(describing: error), privacy: .public)")
            }
        }
        endpoints = OpenAICompatibleEndpoint.known.map { known in saved.first { $0.id == known.id } ?? known }
            + saved.filter { $0.kind == .custom }
        consents = Set(defaults.stringArray(forKey: Self.consentsKey) ?? [])
        localModelID = defaults.string(forKey: Self.localModelKey)
        hasOfferedLocalModel = defaults.bool(forKey: Self.localModelOfferedKey)
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// The endpoints that can answer: a model is written for them.
    var ready: [OpenAICompatibleEndpoint] {
        endpoints.filter { !$0.model.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The Modello locale: the endpoint on the Mac the user set, while it has a model.
    var localModel: OpenAICompatibleEndpoint? {
        ready.first { $0.id == localModelID && $0.isOnMac }
    }

    /// Makes `endpoint`, on the Mac, the Modello locale; `nil` leaves none.
    func setLocalModel(_ endpoint: OpenAICompatibleEndpoint?) {
        localModelID = endpoint?.id
        defaults.set(localModelID, forKey: Self.localModelKey)
    }

    /// Remembers that the Modello locale was proposed, so that it never is again.
    func markLocalModelOffered() {
        hasOfferedLocalModel = true
        defaults.set(true, forKey: Self.localModelOfferedKey)
    }

    /// Saves `endpoint`, replacing the one with its id or adding it at the end.
    func save(_ endpoint: OpenAICompatibleEndpoint) {
        if let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) {
            endpoints[index] = endpoint
        } else {
            endpoints.append(endpoint)
        }
        persist()
    }

    /// Removes the custom `endpoint` and its consent; the known ones stay.
    func remove(_ endpoint: OpenAICompatibleEndpoint) {
        guard endpoint.kind == .custom else { return }
        endpoints.removeAll { $0.id == endpoint.id }
        consents.remove(endpoint.id)
        consents.remove(EndpointBrainContext.notesConsentID(of: endpoint))
        persist()
    }

    /// Allows `endpoint` to receive Domande from now on; the user gave it, never Bubo on its own.
    func grantConsent(to endpoint: OpenAICompatibleEndpoint) {
        grantConsent(toProvider: endpoint.id)
    }

    /// Takes back the consent of `endpoint`, and the one for the notes: it receives nothing more until the user allows
    /// it again.
    func revokeConsent(of endpoint: OpenAICompatibleEndpoint) {
        consents.remove(EndpointBrainContext.notesConsentID(of: endpoint))
        revokeConsent(ofProvider: endpoint.id)
    }

    /// Allows the cloud provider `id`, an endpoint or GitHub Copilot, to receive what the user sends it.
    func grantConsent(toProvider id: String) {
        consents.insert(id)
        persist()
    }

    /// Takes back the consent of the cloud provider `id`: it receives nothing more until the user allows it again.
    func revokeConsent(ofProvider id: String) {
        consents.remove(id)
        persist()
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(endpoints), forKey: Self.endpointsKey)
        } catch {
            Logger(subsystem: "com.mgiuditta.bubo", category: "router")
                .error("Endpoints not saved: \(String(describing: error), privacy: .public)")
        }
        defaults.set(consents.sorted(), forKey: Self.consentsKey)
    }

    private static let endpointsKey = "router.endpoints"
    private static let consentsKey = "router.cloudConsents"
    private static let localModelKey = "router.localModel"
    private static let localModelOfferedKey = "router.localModelOffered"
}
