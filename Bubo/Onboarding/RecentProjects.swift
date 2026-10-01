import Foundation

/// A Progetto the user worked on with `claude`, proposed at the first launch.
nonisolated struct RecentProject: Identifiable, Hashable, Sendable {
    /// The Progetto's folder.
    let folder: URL
    /// Whether the folder is in a place macOS protects, such as Documenti: Bubo never looked inside it, so choosing it
    /// goes through the Open panel, which counts as consent.
    let isProtected: Bool

    var id: URL { folder }
}

/// The Progetti of `claude`, most recent first, from the keys of `projects` in `~/.claude.json` (spec 26).
///
/// Only the keys are read: the rest of the file, which also holds the login, is never kept or logged. Folders in
/// protected places are never touched, so no system alert appears.
nonisolated enum RecentProjects {
    /// What `RecentProjects` reads from the disk; tests pass a fake one that records each call.
    struct FileSystem: Sendable {
        /// The contents of a file, or `nil` if it cannot be read.
        var contents: @Sendable (URL) -> Data?
        /// What is at a path: `true` for a folder, `false` for a file, `nil` for nothing.
        var isFolder: @Sendable (URL) -> Bool?
        /// When the item at a path last changed, or `nil` if there is none.
        var modificationDate: @Sendable (URL) -> Date?

        /// The real disk.
        static let live = FileSystem(
            contents: { try? Data(contentsOf: $0) },
            isFolder: { url in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
                return isDirectory.boolValue
            },
            modificationDate: { url in
                (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            }
        )
    }

    /// Up to `limit` Progetti, most recent first.
    ///
    /// Leaves out the home, `/`, folders that are gone and worktrees, where `.git` is a file. Orders by when
    /// `claude` last wrote in the Progetto's folder in `~/.claude/projects`, whose name comes from the path.
    static func load(home: URL = .homeDirectory, limit: Int = 3, fileSystem: FileSystem = .live) -> [RecentProject] {
        guard let data = fileSystem.contents(home.appending(path: ".claude.json")),
              let paths = try? JSONDecoder().decode(ProjectPaths.self, from: data).paths
        else { return [] }
        let homePath = home.standardizedFileURL.path
        let history = home.appending(path: ".claude/projects", directoryHint: .isDirectory)
        let projects: [(project: RecentProject, date: Date?)] = paths.compactMap { path in
            let folder = URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL
            guard path.hasPrefix("/"), folder.path != "/", folder.path != homePath else { return nil }
            let isProtected = isProtected(folder.path, home: homePath)
            if !isProtected {
                guard fileSystem.isFolder(folder) == true,
                      fileSystem.isFolder(folder.appending(path: ".git")) != false
                else { return nil }
            }
            let date = fileSystem.modificationDate(history.appending(path: encodedName(of: path)))
            return (RecentProject(folder: folder, isProtected: isProtected), date)
        }
        return projects
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .prefix(limit)
            .map(\.project)
    }

    /// The name of the folder where `claude` keeps the conversations of `path`: every character that is not an ASCII
    /// letter or digit becomes `-`. Computed from the path, never turned back into one: the two are not one to one.
    static func encodedName(of path: String) -> String {
        String(path.unicodeScalars.map { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar)) ? Character(scalar) : "-"
        })
    }

    /// Whether `path` is where macOS asks before an app looks: Scrivania, Documenti, Download, iCloud Drive, or
    /// another volume.
    static func isProtected(_ path: String, home: String) -> Bool {
        let roots = ["Desktop", "Documents", "Downloads", "Library/Mobile Documents"].map { "\(home)/\($0)" }
            + ["/Volumes"]
        return roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}

/// The keys of `projects` in `.claude.json`, and nothing else of the file.
private nonisolated struct ProjectPaths: Decodable {
    let paths: [String]

    init(from decoder: any Decoder) throws {
        let file = try decoder.container(keyedBy: Key.self)
        paths = (try? file.nestedContainer(keyedBy: Key.self, forKey: Key(stringValue: "projects")))?
            .allKeys.map(\.stringValue) ?? []
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
