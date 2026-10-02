import Foundation
import Testing
@testable import Bubo

@MainActor
struct AutomationStoreTests {
    let base = FileManager.default.temporaryDirectory.appending(path: "Automazioni-\(UUID().uuidString)")

    private func automation(in project: URL) -> Automation {
        Automation(id: UUID(), name: "Test notturni", project: project, request: "Lancia i test")
    }

    // Criterio 2: la Regola approvata è quella proposta, non allargata, e resta dopo un riavvio.
    @Test func allowingADenialSavesItsSuggestedRuleAsItArrives() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let file = base.appending(path: "Automazioni.json")
        let store = AutomationStore(file: file)
        let automation = automation(in: base)
        store.add(automation)

        #expect(store.allow("Bash(npm test)", in: automation.id))
        #expect(store.allow("Bash(npm test)", in: automation.id))

        #expect(store[automation.id]?.rules == ["Bash(npm test)"])
        #expect(AutomationStore(file: file)[automation.id]?.rules == ["Bash(npm test)"])
    }

    // Criterio 3: dai livelli 4–5 non nasce mai una Regola.
    @Test(arguments: ["Bash(rm *)", "Bash(git push *)", "Bash", "Edit(~/.ssh/**)", "Bash(rm -rf /)"])
    func aLevelFourOrFiveRuleIsNeverSaved(rule: String) {
        let store = AutomationStore()
        let automation = automation(in: base)
        store.add(automation)
        #expect(!store.allow(rule, in: automation.id))
        #expect(store[automation.id]?.rules == [])
    }

    // #388: togliere una Regola dalle Impostazioni la toglie dall'Automazione, anche dopo un riavvio.
    @Test func revokingARuleRemovesItFromTheAutomation() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        let file = base.appending(path: "Automazioni.json")
        let store = AutomationStore(file: file)
        let automation = automation(in: base)
        store.add(automation)
        store.allow("Bash(npm test)", in: automation.id)
        store.allow("Bash(npm run lint)", in: automation.id)

        store.revoke("Bash(npm test)", in: automation.id)

        #expect(store[automation.id]?.rules == ["Bash(npm run lint)"])
        #expect(AutomationStore(file: file)[automation.id]?.rules == ["Bash(npm run lint)"])
    }

    @Test func aRuleForAnAutomationThatIsGoneIsNotSaved() {
        #expect(!AutomationStore().allow("Bash(npm test)", in: UUID()))
    }

    // Criterio 4: le Regole dell'Automazione non toccano mai i settings di `claude`.
    @Test func theAutomationsRulesNeverReachTheClaudeSettings() throws {
        let repos = try WorktreeManagerTests()
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let repo = try repos.makeRepo("repo", files: [".claude/settings.local.json": #"{"permissions":{"allow":["Bash(ls)"]}}"#])
        let settings = repo.appending(path: ".claude/settings.local.json")
        let before = try Data(contentsOf: settings)
        let store = AutomationStore(file: repos.base.appending(path: "Automazioni.json"))
        let automation = automation(in: repo)
        store.add(automation)

        store.allow("Bash(npm test)", in: automation.id)

        #expect(try Data(contentsOf: settings) == before)
        #expect(!FileManager.default.fileExists(atPath: repo.appending(path: ".claude/settings.json").path))
    }

    @Test func aNonGitProjectNeverRunsAutonomous() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let repos = try WorktreeManagerTests()
        defer { try? FileManager.default.removeItem(at: repos.base) }
        let repo = try repos.makeRepo("repo")
        let store = AutomationStore()
        let outside = automation(in: base)
        let inside = automation(in: repo)

        store.add(outside)
        store.add(inside)

        #expect(store[outside.id]?.isAutonomous == false)
        #expect(store[inside.id]?.isAutonomous == true)
    }

    @Test func removingAnAutomationTakesItsRulesAway() {
        let store = AutomationStore()
        let automation = automation(in: base)
        store.add(automation)
        store.allow("Bash(npm test)", in: automation.id)
        store.remove(automation.id)
        #expect(store.automations.isEmpty)
    }
}
