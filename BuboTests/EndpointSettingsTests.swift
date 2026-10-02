import Foundation
import Testing
@testable import Bubo

struct EndpointSettingsTests {
    let defaults = UserDefaults(suiteName: "EndpointSettingsTests-\(UUID().uuidString)")!

    @Test func theKnownEndpointsAreThereWithNoModel() {
        let settings = EndpointSettings(defaults: defaults)

        #expect(settings.endpoints.map(\.kind) == [.openAI, .gemini, .openRouter, .ollama, .lmStudio])
        #expect(settings.ready.isEmpty)
        #expect(settings.endpoints.filter(\.isOnMac).map(\.kind) == [.ollama, .lmStudio])
    }

    @Test func modelsAndConsentsSurviveARelaunch() {
        let settings = EndpointSettings(defaults: defaults)
        var openAI = settings.endpoints[0]
        openAI.model = "gpt-prova"
        settings.save(openAI)
        settings.grantConsent(to: openAI)
        let custom = OpenAICompatibleEndpoint.custom(named: "xAI", at: URL(string: "https://api.x.ai/v1")!)
        settings.save(custom)

        let relaunched = EndpointSettings(defaults: defaults)

        #expect(relaunched.endpoints.first?.model == "gpt-prova")
        #expect(relaunched.consents == [openAI.id])
        #expect(relaunched.endpoints.last == custom)
        #expect(relaunched.endpoints.last?.provider == .xAI)
    }

    @Test func aRevokedConsentIsGone() {
        let settings = EndpointSettings(defaults: defaults)
        settings.grantConsent(to: settings.endpoints[1])
        settings.revokeConsent(of: settings.endpoints[1])

        #expect(EndpointSettings(defaults: defaults).consents.isEmpty)
    }
}
