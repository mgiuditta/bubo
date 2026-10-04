import Foundation
import Testing
@testable import Bubo

struct RuleListingTests {
    let base = FileManager.default.temporaryDirectory.appending(path: "Regole-\(UUID().uuidString)")

    private func write(_ json: String, at path: String) throws -> URL {
        let url = base.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
        return url
    }

    // Criterio 1: regole ovunque, per Progetto e per Automazione, ciascuna con la sua origine.
    @Test func everyRuleShowsWhereItCounts() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let user = try write(#"{"permissions":{"allow":["Read"]}}"#, at: "home/settings.json")
        _ = try write(#"{"permissions":{"allow":["Bash(npm test)"]}}"#, at: "app/.claude/settings.local.json")
        _ = try write(#"{"permissions":{"allow":["WebFetch(domain:swift.org)"]}}"#, at: "app/.claude/settings.json")
        let project = base.appending(path: "app")
        var automation = Automation(id: UUID(), name: "Test notturni", project: project, request: "Lancia i test")
        automation.rules = ["Bash(swift test)"]

        let listing = RuleListing(projects: [project, project], automations: [.init(automation)], userSettings: user)

        #expect(listing.groups.map(\.scope) == [
            .everywhere,
            .project(URL(filePath: TrustGate.root(of: project), directoryHint: .isDirectory)),
            .automation(id: automation.id, name: "Test notturni"),
        ])
        #expect(listing.groups.map { $0.items.map(\.rule) } == [
            ["Read"], ["Bash(npm test)", "WebFetch(domain:swift.org)"], ["Bash(swift test)"],
        ])
        #expect(listing.groups.map { $0.items.map(\.origin) } == [
            [.userSettings], [.localSettings, .sharedSettings], [.automation],
        ])
        #expect(listing.unreadableFiles.isEmpty)
    }

    // Criterio 2: si tolgono solo le regole che Bubo scrive; le altre si vedono e basta.
    @Test(arguments: [
        (RuleListing.Origin.userSettings, false), (.sharedSettings, false), (.localSettings, true), (.automation, true),
    ])
    func onlyBubosOwnRulesCanBeRemoved(origin: RuleListing.Origin, isRemovable: Bool) {
        #expect(RuleListing.Item(rule: "Read", origin: origin, level: .lettura).isRemovable == isRemovable)
    }

    // Criterio 2: il Livello di rischio di una regola è quello della chiamata peggiore che consente.
    @Test func eachRuleCarriesItsRiskLevel() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let user = try write(#"{"permissions":{"allow":["Bash(git status)","Bash(git push *)"]}}"#, at: "home/settings.json")

        let items = RuleListing(projects: [], automations: [], userSettings: user).groups[0].items

        #expect(items.map(\.level) == [.lettura, .irreversibile])
    }

    @Test func anUnreadableFileIsReportedAndAddsNoRule() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let user = try write("{ non è JSON", at: "home/settings.json")

        let listing = RuleListing(projects: [], automations: [], userSettings: user)

        #expect(listing.unreadableFiles == [user])
        #expect(listing.groups.map(\.items) == [[]])
    }

    @Test func aProjectOrAnAutomationWithoutRulesIsLeftOut() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let automation = Automation(id: UUID(), name: "Vuota", project: base, request: "Niente")

        let listing = RuleListing(projects: [base], automations: [.init(automation)],
                                  userSettings: base.appending(path: "manca.json"))

        #expect(listing.groups.map(\.scope) == [.everywhere])
    }
}
