import Foundation
import Sparkle
import Testing
@testable import Bubo

/// The Canale and the choices of Impostazioni › Aggiornamenti, without starting Sparkle.
@MainActor
struct UpdateControllerTests {
    private let suiteName = "UpdateControllerTests-\(UUID().uuidString)"

    @Test func betaIsOffByDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(!UpdateController(defaults: defaults, isEnabled: false).receivesBeta)
    }

    @Test(arguments: [false, true])
    func allowedChannelsFollowTheBetaToggle(receivesBeta: Bool) throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let updates = UpdateController(defaults: defaults, isEnabled: false)
        updates.receivesBeta = receivesBeta
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                                 userDriver: SPUStandardUserDriver(hostBundle: .main, delegate: nil), delegate: nil)
        #expect(updates.allowedChannels(for: updater) == (receivesBeta ? ["beta"] : []))
        #expect(defaults.bool(forKey: UpdateController.receivesBetaKey) == receivesBeta)
    }

    @Test func aBuildThatCannotUpdateNeverChecks() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let updates = UpdateController(defaults: defaults, isEnabled: false)
        updates.start()
        #expect(!updates.canCheckForUpdates)
    }
}
