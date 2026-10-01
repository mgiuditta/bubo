import Foundation
import Testing
@testable import Bubo

/// The frontmatter of an agent's file, as the Agenti window reads it.
struct AgentFileTests {
    let file = URL(filePath: "/r/.claude/agents/revisore.md")
    let folder = URL(filePath: "/r/.claude/agents", directoryHint: .isDirectory)

    func parse(_ text: String, namespace: [String] = []) -> AgentFile? {
        AgentFile(text: text, file: file, folder: folder, source: .project, namespace: namespace)
    }

    @Test func plainFieldsAndCommaSeparatedTools() throws {
        let agent = try #require(parse("""
            ---
            name: revisore
            description: Rivede il codice dopo ogni modifica # commento
            tools: Read, Grep, Glob
            model: sonnet
            ---
            Sei un revisore.
            """))
        #expect(agent.name == "revisore")
        #expect(agent.description == "Rivede il codice dopo ogni modifica")
        #expect(agent.tools == ["Read", "Grep", "Glob"])
        #expect(agent.model == "sonnet")
        #expect(agent.identifier == "revisore")
    }

    @Test func quotedScalarsBlocksAndLists() throws {
        let agent = try #require(parse("""
            ---\r
            name: "revisore"\r
            description: >\r
              Rivede il codice:\r
              solo in lettura.\r
            tools:\r
              - Read\r
              - 'Bash(git diff:*)'\r
            hooks:\r
              PreToolUse:\r
                - matcher: Bash\r
            ---\r
            """))
        #expect(agent.name == "revisore")
        #expect(agent.description == "Rivede il codice: solo in lettura.")
        #expect(agent.tools == ["Read", "Bash(git diff:*)"])
        #expect(agent.model == nil)
    }

    @Test func literalBlockAndFlowList() throws {
        let agent = try #require(parse("""
            ---
            name: scrittore
            description: |
              Prima riga
              seconda riga
            tools: [Read, Write]
            ---
            """))
        #expect(agent.description == "Prima riga\nseconda riga")
        #expect(agent.tools == ["Read", "Write"])
    }

    @Test func escapesInDoubleQuotes() throws {
        let agent = try #require(parse(#"""
            ---
            name: citazioni
            description: "Dice \"ciao\" e va \\ a capo"
            ---
            """#))
        #expect(agent.description == #"Dice "ciao" e va \ a capo"#)
    }

    @Test func noToolsMeansEveryTool() throws {
        let agent = try #require(parse("---\nname: a\ndescription: b\n---\n"))
        #expect(agent.tools == nil)
    }

    @Test(arguments: [
        "name: a\ndescription: b\n",
        "---\nname: a\ndescription: b\n",
        "---\nname: a\n---\n",
        "---\ndescription: b\n---\n",
        "---\nname: \"\"\ndescription: b\n---\n",
    ])
    func withoutAValidFrontmatterThereIsNoAgent(text: String) {
        #expect(parse(text) == nil)
    }

    @Test func aPluginsAgentIsNamespaced() throws {
        let agent = try #require(parse("---\nname: revisore\ndescription: b\n---\n", namespace: ["qualita", "codice"]))
        #expect(agent.identifier == "qualita:codice:revisore")
    }
}

/// The folders of a Progetto on disk, in a temporary folder that the suite deletes.
final class AgentFolders: Sendable {
    let base: URL
    let repo: URL
    let user: URL

    init() {
        base = URL(filePath: TrustGate.realPath(FileManager.default.temporaryDirectory.path), directoryHint: .isDirectory)
            .appending(path: "Agenti-\(UUID().uuidString)", directoryHint: .isDirectory)
        repo = base.appending(path: "repo", directoryHint: .isDirectory)
        user = base.appending(path: "utente", directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: base)
    }

    /// Writes the agent `name` described by `description` at `path`, under the base folder.
    @discardableResult
    func agent(_ name: String, description: String = "Fa qualcosa", at path: String) throws -> URL {
        let file = base.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("---\nname: \(name)\ndescription: \(description)\n---\n".utf8).write(to: file)
        return file
    }

    func makeRepo() throws {
        try FileManager.default.createDirectory(at: repo.appending(path: ".git"), withIntermediateDirectories: true)
    }

    /// Every path under the base folder.
    func contents() -> Set<String> {
        Set(FileManager.default.enumerator(atPath: base.path)?.compactMap { $0 as? String } ?? [])
    }

    /// The catalog of `project`, with `loaded` as `claude`'s answer.
    func catalog(of project: URL, plugins: [ClaudeConfiguration.Plugin] = [], loaded: [ClaudeConfiguration.Agent]? = nil,
                 loadsProject: Bool = true) async -> AgentCatalog {
        let folders = AgentCatalog.folders(project: project, user: user, plugins: plugins)
        return AgentCatalog(folders: folders, files: await AgentCatalog.files(in: folders), loaded: loaded,
                            loadsProject: loadsProject)
    }
}

/// The name conflicts of the Agenti window and who wins them, with the precedence of the Claude Code documentation.
struct AgentCatalogTests {
    let folders = AgentFolders()

    @Test func theProgettoWinsOverTheUser() async throws {
        try folders.makeRepo()
        let project = try folders.agent("revisore", at: "repo/.claude/agents/revisore.md")
        let user = try folders.agent("revisore", at: "utente/agents/revisore.md")

        let entry = try #require(await folders.catalog(of: folders.repo).entries.first { $0.name == "revisore" })

        #expect(entry.hasConflict)
        #expect(entry.winner?.file == project)
        #expect(entry.covered.map(\.file) == [user])
        #expect(entry.source == .project)
    }

    @Test func theFolderClosestToTheProgettoWins() async throws {
        try folders.makeRepo()
        let outer = try folders.agent("revisore", at: "repo/.claude/agents/revisore.md")
        let inner = try folders.agent("revisore", at: "repo/app/.claude/agents/revisore.md")

        let catalog = await folders.catalog(of: folders.repo.appending(path: "app", directoryHint: .isDirectory))
        let entry = try #require(catalog.entries.first { $0.name == "revisore" })

        #expect(entry.winner?.file == inner)
        #expect(entry.covered.map(\.file) == [outer])
    }

    @Test func outsideTheRepoNoFolderAboveCounts() async throws {
        try folders.agent("revisore", at: ".claude/agents/revisore.md")
        try folders.makeRepo()

        let catalog = await folders.catalog(of: folders.repo)

        #expect(catalog.entries.isEmpty)
    }

    @Test func theIdentityIsTheNameNotTheFile() async throws {
        try folders.makeRepo()
        try folders.agent("revisore", at: "repo/.claude/agents/a.md")
        try folders.agent("revisore", at: "repo/.claude/agents/sotto/b.md")

        let entry = try #require(await folders.catalog(of: folders.repo).entries.first)

        #expect(entry.name == "revisore")
        #expect(entry.files.count == 2)
        #expect(entry.isUndecided)
        #expect(entry.winner == nil)
    }

    @Test func claudesAnswerTellsDuplicatesInOneFolderApart() async throws {
        try folders.makeRepo()
        try folders.agent("revisore", description: "Prima", at: "repo/.claude/agents/a.md")
        let second = try folders.agent("revisore", description: "Seconda", at: "repo/.claude/agents/b.md")

        let catalog = await folders.catalog(of: folders.repo,
                                            loaded: [.init(name: "revisore", description: "Seconda", model: nil)])
        let entry = try #require(catalog.entries.first)

        #expect(!entry.isUndecided)
        #expect(entry.winner?.file == second)
    }

    @Test func everyConflictIsShown() async throws {
        try folders.makeRepo()
        // Progetto and user, nested folders, one folder: three conflicts; two names without one.
        try folders.agent("uno", at: "repo/.claude/agents/uno.md")
        try folders.agent("uno", at: "utente/agents/uno.md")
        try folders.agent("due", at: "repo/.claude/agents/due.md")
        try folders.agent("due", at: "repo/app/.claude/agents/due.md")
        try folders.agent("tre", at: "utente/agents/tre.md")
        try folders.agent("tre", at: "utente/agents/altro/tre-bis.md")
        try folders.agent("solo", at: "repo/.claude/agents/solo.md")
        try folders.agent("mio", at: "utente/agents/mio.md")

        let catalog = await folders.catalog(of: folders.repo.appending(path: "app", directoryHint: .isDirectory))

        #expect(Set(catalog.entries.filter(\.hasConflict).map(\.name)) == ["uno", "due", "tre"])
        #expect(catalog.entries.first { $0.name == "uno" }?.winner?.source == .project)
        #expect(catalog.entries.first { $0.name == "due" }?.winner?.file.path.contains("/app/") == true)
        #expect(catalog.entries.first { $0.name == "tre" }?.isUndecided == true)
    }

    @Test func aPluginsAgentHasItsOwnName() async throws {
        try folders.makeRepo()
        try folders.agent("revisore", at: "utente/agents/revisore.md")
        try folders.agent("revisore", at: "plugin/qualita/agents/revisore.md")
        let plugin = ClaudeConfiguration.Plugin(name: "qualita", version: nil,
                                                path: folders.base.appending(path: "plugin/qualita").path)

        let catalog = await folders.catalog(of: folders.repo, plugins: [plugin])

        let names = catalog.entries.map(\.name)
        #expect(names == ["qualita:revisore", "revisore"])
        #expect(catalog.entries.allSatisfy { !$0.hasConflict })
        #expect(catalog.entries.first?.source == .plugin("qualita"))
    }

    @Test func anUntrustedProgettosAgentsDoNotCount() async throws {
        try folders.makeRepo()
        try folders.agent("revisore", at: "repo/.claude/agents/revisore.md")
        let user = try folders.agent("revisore", at: "utente/agents/revisore.md")
        try folders.agent("locale", at: "repo/.claude/agents/locale.md")

        let catalog = await folders.catalog(of: folders.repo, loadsProject: false)

        #expect(catalog.entries.first { $0.name == "revisore" }?.winner?.file == user)
        let local = try #require(catalog.entries.first { $0.name == "locale" })
        #expect(local.isIgnored)
        #expect(local.winner == nil && !local.isUndecided)
    }

    @Test func aBuiltInAgentHasNoFile() async throws {
        try folders.makeRepo()

        let catalog = await folders.catalog(of: folders.repo,
                                            loaded: [.init(name: "Explore", description: "Cerca", model: "haiku")])
        let entry = try #require(catalog.entries.first)

        #expect(entry.source == nil)
        #expect(entry.files.isEmpty && !entry.isUndecided)
        #expect(catalog.descriptionTokens == 0)
    }

    @Test func overFifteenThousandTokensOfDescriptionsWarns() async throws {
        try folders.makeRepo()
        // 4 characters a token: 30,000 characters each are 7,500 tokens.
        try folders.agent("uno", description: String(repeating: "a", count: 30_000), at: "repo/.claude/agents/uno.md")
        try folders.agent("due", description: String(repeating: "b", count: 30_000), at: "utente/agents/due.md")
        #expect(await !folders.catalog(of: folders.repo).exceedsDescriptionBudget)

        // A covered file does not count; a winning one does.
        try folders.agent("due", description: "corta", at: "repo/.claude/agents/due.md")
        try folders.agent("tre", description: String(repeating: "c", count: 40), at: "repo/.claude/agents/tre.md")
        #expect(await !folders.catalog(of: folders.repo).exceedsDescriptionBudget)
        try folders.agent("quattro", description: String(repeating: "d", count: 30_100), at: "utente/agents/quattro.md")

        let catalog = await folders.catalog(of: folders.repo)
        #expect(catalog.descriptionTokens > AgentCatalog.descriptionTokenBudget)
        #expect(catalog.exceedsDescriptionBudget)
    }
}

/// Nuovo agente: the minimal file, only on a click, never over a name already there.
struct AgentFileWriterTests {
    let folders = AgentFolders()

    func writer() async -> AgentFileWriter {
        let catalogFolders = AgentCatalog.folders(project: folders.repo, user: folders.user, plugins: [])
        let files = await AgentCatalog.files(in: catalogFolders).filter { $0.source == .project }
        return AgentFileWriter(folder: folders.repo.appending(path: ".claude/agents", directoryHint: .isDirectory),
                               existing: files)
    }

    @Test func aNameAlreadyInTheSourceIsRefusedWithItsFile() async throws {
        try folders.makeRepo()
        let taken = try folders.agent("revisore", at: "repo/.claude/agents/sotto/altro-nome.md")

        let refusal = await writer().refusal(name: "revisore", description: "Rivede")

        #expect(refusal == .nameTaken(taken))
    }

    @Test func aFileWithTheNameIsRefused() async throws {
        try folders.makeRepo()
        try folders.agent("altro", at: "repo/.claude/agents/revisore.md")

        let refusal = await writer().refusal(name: "revisore", description: "Rivede")

        #expect(refusal == .fileExists(folders.repo.appending(path: ".claude/agents/revisore.md")))
    }

    @Test(arguments: [
        ("", "Rivede", AgentFileWriter.Refusal.missingName),
        ("plugin:revisore", "Rivede", .invalidName),
        ("-revisore", "Rivede", .invalidName),
        ("Revisore", "Rivede", .invalidName),
        ("re/visore", "Rivede", .invalidName),
        ("revisore", "  ", .missingDescription),
    ])
    func invalidInputIsRefused(name: String, description: String, refusal: AgentFileWriter.Refusal) async throws {
        try folders.makeRepo()
        #expect(await writer().refusal(name: name, description: description) == refusal)
    }

    @Test func nothingIsWrittenWithoutTheClick() async throws {
        try folders.makeRepo()
        try folders.agent("revisore", at: "repo/.claude/agents/revisore.md")
        let before = folders.contents()

        // What the window does until Crea e apri: read the folders, build the catalog, check the name.
        _ = await folders.catalog(of: folders.repo)
        let writer = await writer()
        _ = writer.refusal(name: "nuovo", description: "Fa qualcosa")
        _ = writer.refusal(name: "revisore", description: "Fa qualcosa")
        _ = writer.file(named: "nuovo")

        #expect(folders.contents() == before)
    }

    @Test func theClickWritesTheMinimalFile() async throws {
        try folders.makeRepo()

        let file = try await writer().write(name: "revisore", description: "Rivede \"tutto\":\nsolo in lettura")

        #expect(file == folders.repo.appending(path: ".claude/agents/revisore.md"))
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text == "---\nname: revisore\ndescription: \"Rivede \\\"tutto\\\": solo in lettura\"\n---\n\n")
        // The empty body is the line the editor opens at.
        #expect(text.split(separator: "\n", omittingEmptySubsequences: false)[AgentFileWriter.bodyLine - 1].isEmpty)
        #expect(text.split(separator: "\n", omittingEmptySubsequences: false)[AgentFileWriter.bodyLine - 2] == "---")
        let agent = try #require(AgentFile(text: text, file: file, folder: file.deletingLastPathComponent(), source: .project))
        #expect(agent.name == "revisore")
        #expect(agent.description == "Rivede \"tutto\": solo in lettura")
    }

    @Test func aSecondWriteNeverOverwrites() async throws {
        try folders.makeRepo()
        let first = await writer()
        let file = try first.write(name: "revisore", description: "Prima")

        #expect(throws: AgentFileWriter.Refusal.fileExists(file)) {
            try first.write(name: "revisore", description: "Seconda")
        }
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("Prima"))
    }
}
