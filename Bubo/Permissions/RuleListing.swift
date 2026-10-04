import Foundation

/// Every Regola di permesso Bubo knows, grouped by where it counts: ovunque, in a Progetto, in an Automazione (#388).
///
/// Each rule carries the file or the place it comes from and its Livello di rischio, which is the highest of the calls
/// it would allow.
nonisolated struct RuleListing: Sendable {
    /// What a group of rules belongs to.
    enum Scope: Hashable, Sendable {
        /// The user's rules of `claude`, in every Progetto.
        case everywhere
        /// The rules of the Progetto in this folder.
        case project(URL)
        /// The Regole "in questa Automazione".
        case automation(id: Automation.ID, name: String)
    }

    /// Where a rule is written.
    enum Origin: Hashable, Sendable {
        /// `~/.claude/settings.json`: the user's, never changed by Bubo.
        case userSettings
        /// `.claude/settings.local.json` of the Progetto: the ones "Sempre in questo Progetto" writes.
        case localSettings
        /// `.claude/settings.json` of the Progetto, in git: they belong to the repo.
        case sharedSettings
        /// Bubo's own file of the Automazioni.
        case automation
    }

    /// A rule, where it comes from and how risky the calls it allows are.
    struct Item: Hashable, Sendable, Identifiable {
        let rule: String
        let origin: Origin
        let level: RiskLevel

        var id: Self { self }

        /// Whether Bubo can take it away: only from the files it writes itself.
        var isRemovable: Bool { origin == .localSettings || origin == .automation }
    }

    /// The rules of one Scope.
    struct Group: Sendable, Identifiable {
        let scope: Scope
        let items: [Item]

        var id: Scope { scope }
    }

    /// An Automazione's rules, as the listing reads them.
    struct AutomationRules: Hashable, Sendable {
        let id: Automation.ID
        let name: String
        let project: URL
        let rules: [String]

        init(_ automation: Automation) {
            id = automation.id
            name = automation.name
            project = automation.project
            rules = automation.rules
        }
    }

    /// The rules that count everywhere, then each Progetto's and each Automazione's that have some.
    let groups: [Group]
    /// The settings files whose rules `claude` skips because they cannot be read.
    let unreadableFiles: [URL]

    /// Reads the rules of `projects`, of `automations` and of the user's settings at `userSettings`.
    ///
    /// Two folders of the same Progetto, such as two worktrees, show it once.
    init(projects: [URL], automations: [AutomationRules], userSettings: URL = RuleStore.defaultUserSettings) {
        var unreadable: [URL] = []
        func rules(at url: URL) -> [String] {
            do {
                return try RuleStore.allowRules(at: url)
            } catch {
                unreadable.append(url)
                return []
            }
        }

        let home = RiskClassifier(workingDirectory: URL.homeDirectory)
        var groups = [Group(scope: .everywhere, items: rules(at: userSettings).map {
            Item(rule: $0, origin: .userSettings, level: home.risk(ofRule: $0).level)
        })]

        var seen = Set<String>()
        for folder in projects {
            let store = RuleStore(project: folder)
            guard seen.insert(store.root.path).inserted else { continue }
            let classifier = RiskClassifier(workingDirectory: store.root)
            let items = [(store.file, Origin.localSettings), (store.root.appending(path: ".claude/settings.json"), .sharedSettings)]
                .flatMap { url, origin in
                    rules(at: url).map { Item(rule: $0, origin: origin, level: classifier.risk(ofRule: $0).level) }
                }
            if !items.isEmpty { groups.append(Group(scope: .project(store.root), items: items)) }
        }

        for automation in automations where !automation.rules.isEmpty {
            let classifier = RiskClassifier(workingDirectory: automation.project)
            groups.append(Group(scope: .automation(id: automation.id, name: automation.name), items: automation.rules.map {
                Item(rule: $0, origin: .automation, level: classifier.risk(ofRule: $0).level)
            }))
        }

        self.groups = groups
        unreadableFiles = unreadable
    }
}
