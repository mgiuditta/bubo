import Foundation

/// The skills Claude Code would see in a folder, for the `/` menu and to expand `/name` for every model (#689): the
/// user's `~/.claude/skills` and `~/.claude/commands`, those of the enabled plugins, and the folder's own
/// `.claude/skills` and `.claude/commands`. Only reads.
nonisolated enum SkillCatalog {
    /// The skills for a prompt that works in `folder` (a Progetto, the Secondo cervello, or none), sorted by name; the
    /// folder's own come first when a name repeats, then the user's, then the plugins'.
    @concurrent static func skills(in folder: URL?, home: URL = .homeDirectory,
                                   plugins: PluginFolders = .current()) async -> [Skill] {
        let claude = home.appending(path: ".claude", directoryHint: .isDirectory)
        var found: [Skill] = []
        if let folder {
            found += reading(folder.appending(path: ".claude", directoryHint: .isDirectory), prefix: nil, source: .project)
        }
        found += reading(claude, prefix: nil, source: .user)
        let snapshot = await PluginSnapshot.read(from: plugins, project: folder)
        for plugin in snapshot.plugins where plugin.isEnabled {
            guard let path = plugin.installations.first(where: \.isEnabled)?.installPath else { continue }
            found += reading(path, prefix: plugin.id.name, source: .plugin)
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0.name).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The skills under `root`: `skills/<name>/SKILL.md` and `commands/<name>.md`, named `prefix:name` when given.
    static func reading(_ root: URL, prefix: String?, source: Skill.Source) -> [Skill] {
        let named = { (name: String) in prefix.map { "\($0):\(name)" } ?? name }
        let skills = contents(of: root.appending(path: "skills", directoryHint: .isDirectory)).compactMap { folder in
            Skill(file: folder.appending(path: "SKILL.md"), name: named(folder.lastPathComponent), directory: folder,
                  source: source)
        }
        let commands = contents(of: root.appending(path: "commands", directoryHint: .isDirectory))
            .filter { $0.pathExtension == "md" }
            .compactMap { file in
                Skill(file: file, name: named(file.deletingPathExtension().lastPathComponent), directory: nil,
                      source: source)
            }
        return skills + commands
    }

    private static func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                      options: .skipsHiddenFiles)) ?? []
    }
}
