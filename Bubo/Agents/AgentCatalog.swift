import Foundation

/// An `agents/` folder `claude` reads, recursively, and where its agents come from.
nonisolated struct AgentFolder: Hashable, Sendable {
    let url: URL
    let source: AgentFile.Source
    /// The prefix of the identifiers of its agents: the plugin's name, empty outside a plugin.
    var namespace: [String] = []
}

/// The subagents of a Progetto: those `claude` lists with `supportedAgents()`, joined to the files that declare
/// them, with the name conflicts and who wins each (spec 19).
///
/// Precedence, from the Claude Code documentation: Progetto, the folder closest to the Progetto first, then user,
/// then plugins. Two files with the same name in the same folder have no documented rule: `claude` loads one by
/// the order it reads the folder.
nonisolated struct AgentCatalog: Equatable, Sendable {
    /// One name, with the agent `claude` loaded under it and every file that declares it.
    struct Entry: Equatable, Identifiable, Sendable {
        /// The name Claude delegates by.
        let name: String
        /// What `claude` lists under the name; `nil` when it does not list it, or was not asked.
        let loaded: ClaudeConfiguration.Agent?
        /// The files that declare the name, the winning one first, then by precedence.
        let files: [AgentFile]
        /// The file `claude` uses; `nil` for a built-in agent, and for duplicates in one folder that `claude`'s
        /// answer does not tell apart.
        let winner: AgentFile?
        /// Whether ``files`` are not taken into account: the Progetto's, when it is not trusted.
        let isIgnored: Bool

        var id: String { name }

        /// Whether more than one file declares the name.
        var hasConflict: Bool { files.count > 1 }
        /// Whether the winner is the read order of one folder, with no rule `claude` documents.
        var isUndecided: Bool { winner == nil && hasConflict && !isIgnored }
        /// The files a winner covers: every file but it.
        var covered: [AgentFile] { files.filter { $0 != winner } }
        /// The source of the winner, or of the files when there is no winner; `nil` for a built-in agent.
        var source: AgentFile.Source? { winner?.source ?? files.first?.source }
    }

    /// The token count of the descriptions above which `claude` warns at start.
    static let descriptionTokenBudget = 15_000

    /// The agents, by name.
    let entries: [Entry]

    /// An estimate of the tokens of the descriptions of the winning files, built-in agents excluded: four
    /// characters each.
    var descriptionTokens: Int {
        entries.compactMap(\.winner).reduce(0) { $0 + $1.description.utf8.count } / 4
    }

    /// Whether the descriptions are over ``descriptionTokenBudget``, and `claude` warns at start.
    var exceedsDescriptionBudget: Bool { descriptionTokens > Self.descriptionTokenBudget }

    /// Joins `loaded`, what `claude` listed, to `files`, read from `folders`.
    ///
    /// - Parameters:
    ///   - folders: The folders, in order of precedence.
    ///   - files: The files read from `folders`, each in the order it was read.
    ///   - loaded: The agents `claude` listed; `nil` when it was not asked.
    ///   - loadsProject: Whether `claude` loads the Progetto's agents: not while it is not trusted.
    init(folders: [AgentFolder], files: [AgentFile], loaded: [ClaudeConfiguration.Agent]?, loadsProject: Bool = true) {
        let rank = Dictionary(folders.enumerated().map { ($1.url, $0) }) { first, _ in first }
        func precedence(_ file: AgentFile) -> Int { rank[file.folder] ?? Int.max }
        let listed = Dictionary((loaded ?? []).map { ($0.name, $0) }) { first, _ in first }
        // A plugin's agent under the name `claude` lists, when it is not the one guessed from its subfolders.
        let byName = Dictionary(grouping: files) { file -> String in
            guard case let .plugin(plugin) = file.source, listed[file.identifier] == nil else { return file.identifier }
            let matches = listed.keys.filter { $0.hasPrefix("\(plugin):") && $0.hasSuffix(":\(file.name)") }
            return matches.count == 1 ? matches[0] : file.identifier
        }
        let names = Set(byName.keys).union(listed.keys)
        entries = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
            let all = byName[name] ?? []
            let counted = all.filter { loadsProject || $0.source != .project }
            let ignored = all.filter { !counted.contains($0) }
            // A stable sort: in one folder, the order the files were read in.
            let ranked = counted.enumerated().sorted { lhs, rhs in
                let left = precedence(lhs.element), right = precedence(rhs.element)
                return left == right ? lhs.offset < rhs.offset : left < right
            }.map(\.element)
            let closest = ranked.filter { $0.folder == ranked.first?.folder }
            let winner: AgentFile? = if closest.count == 1 {
                closest[0]
            } else if let description = listed[name]?.description,
                      case let matches = closest.filter({ $0.description == description }), matches.count == 1 {
                matches[0]
            } else {
                nil
            }
            let ordered = (winner.map { [$0] } ?? []) + ranked.filter { $0 != winner } + ignored
            return Entry(name: name, loaded: listed[name], files: ordered, winner: winner,
                         isIgnored: counted.isEmpty && !ignored.isEmpty)
        }
    }

    // MARK: Reading the folders

    /// The `agents/` folders `claude` reads in `project`, in order of precedence: the Progetto's `.claude/agents`,
    /// then those of the folders above it up to the root of its repo, then the user's in `user`, the `~/.claude`
    /// folder, then the plugins'.
    static func folders(project: URL, user: URL, plugins: [ClaudeConfiguration.Plugin]) -> [AgentFolder] {
        var projectFolders: [URL] = []
        // Not `standardizedFileURL`, which turns `/private/var` into `/var`.
        var folder = project
        var candidates = [folder]
        while folder.path != "/" {
            if FileManager.default.fileExists(atPath: folder.appending(path: ".git").path) {
                projectFolders = candidates
                break
            }
            folder = folder.deletingLastPathComponent()
            candidates.append(folder)
        }
        // Outside a repo, only the Progetto's own folder.
        if projectFolders.isEmpty { projectFolders = [project] }
        return projectFolders.map { AgentFolder(url: $0.appending(path: ".claude/agents", directoryHint: .isDirectory),
                                                source: .project) }
            + [AgentFolder(url: user.appending(path: "agents", directoryHint: .isDirectory), source: .user)]
            + plugins.compactMap { plugin in
                plugin.path.map { AgentFolder(url: URL(filePath: $0).appending(path: "agents", directoryHint: .isDirectory),
                                              source: .plugin(plugin.name), namespace: [plugin.name]) }
            }
    }

    /// The agents declared by the Markdown files of `folders` and of their subfolders, each folder in the order the
    /// file system lists it; files without a valid frontmatter are left out, as `claude` does.
    @concurrent static func files(in folders: [AgentFolder]) async -> [AgentFile] {
        readFiles(in: folders)
    }

    /// The agents declared by the Markdown files of `folders`, as ``files(in:)`` reads them, on the caller's thread.
    static func readFiles(in folders: [AgentFolder]) -> [AgentFile] {
        folders.flatMap { folder -> [AgentFile] in
            let paths = FileManager.default.enumerator(atPath: folder.url.path)?.compactMap { $0 as? String } ?? []
            return paths.filter { $0.hasSuffix(".md") }.compactMap { path in
                let file = folder.url.appending(path: path)
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                let subfolders = path.split(separator: "/").dropLast().map(String.init)
                let namespace = folder.namespace.isEmpty ? [] : folder.namespace + subfolders
                return AgentFile(text: text, file: file, folder: folder.url, source: folder.source, namespace: namespace)
            }
        }
    }

    // MARK: Agents of the Automazioni

    /// The user's `~/.claude` folder, where `claude` reads the user's agents.
    static let userFolder = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude",
                                                                                      directoryHint: .isDirectory)

    /// The names of the agents an Automazione can run as in `project`, sorted: those declared by the files of the
    /// Progetto and of the user. The plugins' and the built-in ones are left out: no file of theirs says when they are
    /// gone (spec 19).
    ///
    /// Reads the disk, a few small files.
    static func runnableAgents(in project: URL, user: URL = userFolder) -> [String] {
        let names = Set(readFiles(in: folders(project: project, user: user, plugins: [])).map(\.identifier))
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The folders of `folders` that exist.
    @concurrent static func existing(_ folders: [AgentFolder]) async -> Set<URL> {
        Set(folders.map(\.url).filter { FileManager.default.fileExists(atPath: $0.path) })
    }
}
