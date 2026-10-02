import Foundation
import os

/// The OpenAI-compatible endpoints the user set up, and the clouds among them allowed to receive Domande.
///
/// Kept in the user defaults: addresses, model ids and consents, never a key (those stay in the keychain).
@Observable
final class EndpointSettings {
    /// The one shared by the HUD and the settings window.
    static let shared = EndpointSettings()

    /// The four known endpoints first, then the custom ones in the order they were added.
    private(set) var endpoints: [OpenAICompatibleEndpoint]
    /// The ids of the endpoints in a cloud that is not Claude that the user allowed to receive Domande; revocable.
    private(set) var consents: Set<String>

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
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// The endpoints that can answer: a model is written for them.
    var ready: [OpenAICompatibleEndpoint] {
        endpoints.filter { !$0.model.trimmingCharacters(in: .whitespaces).isEmpty }
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
        persist()
    }

    /// Allows `endpoint` to receive Domande from now on; the user gave it, never Bubo on its own.
    func grantConsent(to endpoint: OpenAICompatibleEndpoint) {
        consents.insert(endpoint.id)
        persist()
    }

    /// Takes back the consent of `endpoint`: it receives nothing more until the user allows it again.
    func revokeConsent(of endpoint: OpenAICompatibleEndpoint) {
        consents.remove(endpoint.id)
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
}
