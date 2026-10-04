import Foundation
import Testing
@testable import Bubo

/// The skills of the `/` menu (#689): the user's, the folder's and the enabled plugins', with their frontmatter.
struct SkillCatalogTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func write(_ text: String, to path: String) throws {
        let file = root.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    @Test func frontmatterGivesNameAndSummary() {
        let (fields, body) = Skill.frontmatter(of: "---\nname: grill-me\ndescription: \"Interview me\"\n---\n\nAsk.\n")
        #expect(fields["name"] == "grill-me")
        #expect(fields["description"] == "Interview me")
        #expect(body.trimmingCharacters(in: .whitespacesAndNewlines) == "Ask.")
        #expect(Skill.frontmatter(of: "Solo testo").body == "Solo testo")
    }

    @Test func userProjectAndPluginSkillsAreFound() async throws {
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        let project = root.appending(path: "progetto", directoryHint: .isDirectory)
        try write("---\ndescription: Utente\n---\nU", to: "home/.claude/skills/tdd/SKILL.md")
        try write("Comando", to: "home/.claude/commands/rivedi.md")
        try write("---\ndescription: Progetto\n---\nP", to: "progetto/.claude/skills/tdd/SKILL.md")
        try write("---\nname: wizard\n---\nW", to: "plugin/skills/w/SKILL.md")
        try write("{\"version\":2,\"plugins\":{\"mp@m\":[{\"scope\":\"user\",\"installPath\":\"\(root.path)/plugin\",\"version\":\"1\"}]}}",
                  to: "plugins/installed_plugins.json")
        try write("{\"enabledPlugins\":{\"mp@m\":true}}", to: "home/.claude/settings.json")
        let folders = PluginFolders(root: root.appending(path: "plugins", directoryHint: .isDirectory),
                                    userSettings: home.appending(path: ".claude/settings.json"))

        let skills = await SkillCatalog.skills(in: project, home: home, plugins: folders)

        #expect(skills.map(\.name) == ["mp:wizard", "rivedi", "tdd"])
        // The folder's own wins over the user's of the same name.
        #expect(skills.first { $0.name == "tdd" }?.summary == "Progetto")
        #expect(skills.first { $0.name == "rivedi" }?.directory == nil)
        #expect(skills.first { $0.name == "mp:wizard" }?.source == .plugin)
    }

    @Test func disabledPluginsAreLeftOut() async throws {
        let home = root.appending(path: "home", directoryHint: .isDirectory)
        try write("W", to: "plugin/skills/w/SKILL.md")
        try write("{\"version\":2,\"plugins\":{\"mp@m\":[{\"scope\":\"user\",\"installPath\":\"\(root.path)/plugin\",\"version\":\"1\"}]}}",
                  to: "plugins/installed_plugins.json")
        try write("{\"enabledPlugins\":{\"mp@m\":false}}", to: "home/.claude/settings.json")
        let folders = PluginFolders(root: root.appending(path: "plugins", directoryHint: .isDirectory),
                                    userSettings: home.appending(path: ".claude/settings.json"))

        #expect(await SkillCatalog.skills(in: nil, home: home, plugins: folders).isEmpty)
    }
}
