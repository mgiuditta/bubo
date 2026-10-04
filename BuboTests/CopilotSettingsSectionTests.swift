import Testing
@testable import Bubo

@MainActor
struct CopilotSettingsSectionTests {
    @Test(arguments: [
        (CopilotReadiness.missing, String(localized: "Manca la CLI copilot.")),
        (.signedOut(version: "1.0.0"), String(localized: "Copilot non è collegato.")),
        (.free(version: "1.0.0", account: "octocat"), String(localized: "Collegato come \("octocat") con Copilot Free")),
        (.free(version: "1.0.0", account: nil), String(localized: "Collegato con Copilot Free")),
        (.ready(version: "1.0.0", account: "octocat"), String(localized: "Collegato come \("octocat")")),
        (.ready(version: "1.0.0", account: nil), String(localized: "Collegato")),
    ])
    func statusNamesEachState(readiness: CopilotReadiness, expected: String) {
        #expect(CopilotSettingsSection.status(of: readiness) == expected)
    }
}
