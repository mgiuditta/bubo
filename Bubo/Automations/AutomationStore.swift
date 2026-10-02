import Foundation
import os

/// The Automazioni, kept in a JSON file next to the Sessioni's, with their Regole "in questa Automazione".
///
/// Those rules live only here: they never reach `settings.local.json` nor any other settings of `claude`.
@Observable
final class AutomationStore {
    /// The Automazioni, oldest first.
    private(set) var automations: [Automation] = []

    @ObservationIgnored private let file: URL?

    /// Creates a store kept in `file`; `nil` keeps the Automazioni only in memory.
    init(file: URL? = nil) {
        self.file = file
        guard let file else { return }
        do {
            automations = try JSONDecoder().decode([Automation].self, from: Data(contentsOf: file))
        } catch CocoaError.fileReadNoSuchFile {
        } catch {
            Logger.automations.error("Automazioni unreadable: \(error)")
        }
    }

    /// The Automazione `id`, if it is still there.
    subscript(id: Automation.ID) -> Automation? {
        automations.first { $0.id == id }
    }

    /// Adds `automation`, at the end; outside git its Modalità autonoma is off, since it has no copy of its own.
    func add(_ automation: Automation) {
        var automation = automation
        if !Self.isGitRepository(automation.project) { automation.isAutonomous = false }
        automations.append(automation)
        save()
    }

    /// Replaces the Automazione with the same id, if it is still there.
    func update(_ automation: Automation) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        automations[index] = automation
        save()
    }

    /// Removes the Automazione `id`; its rules go with it.
    func remove(_ id: Automation.ID) {
        automations.removeAll { $0.id == id }
        save()
    }

    /// Adds `rule` to the Regole of the Automazione `id`, exactly as `claude` proposed it, from its next Esecuzione.
    ///
    /// - Returns: Whether the rule is among them now: never for a rule of level 4–5 or touching a critical path,
    ///   since no Regola di permesso comes from those (`CONTEXT.md`), nor for an Automazione that is gone.
    @discardableResult
    func allow(_ rule: String, in id: Automation.ID) -> Bool {
        guard let index = automations.firstIndex(where: { $0.id == id }) else { return false }
        let risk = RiskClassifier(workingDirectory: automations[index].project).risk(ofRule: rule)
        guard !risk.level.isDangerous, !risk.isCritical else { return false }
        if !automations[index].rules.contains(rule) {
            automations[index].rules.append(rule)
            save()
        }
        return true
    }

    /// Records `execution` as the latest of the Automazione `id`.
    func record(_ execution: Execution, for id: Automation.ID) {
        guard let index = automations.firstIndex(where: { $0.id == id }) else { return }
        automations[index].lastExecution = execution
        save()
    }

    /// Whether `folder` is in a git repo, so that an Esecuzione there gets a worktree of its own.
    nonisolated static func isGitRepository(_ folder: URL) -> Bool {
        var path = folder.standardizedFileURL.path
        while true {
            if FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git")) { return true }
            guard path != "/", !path.isEmpty else { return false }
            path = (path as NSString).deletingLastPathComponent
        }
    }

    private func save() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(automations).write(to: file, options: .atomic)
        } catch {
            Logger.automations.error("Automazioni not saved: \(error)")
        }
    }
}

extension Logger {
    nonisolated static let automations = Logger(subsystem: "com.mgiuditta.bubo", category: "automations")
}
