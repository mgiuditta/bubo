import Foundation

/// The folder the user chose as Secondo cervello: its path, and a bookmark to follow it when it is moved.
///
/// Bubo is not sandboxed, so the bookmark grants nothing: it only finds the folder again under a new name.
nonisolated struct SecondBrainLocation: Codable, Equatable, Sendable {
    /// The folder's path when it was last found.
    var path: String
    /// A bookmark to the folder; `nil` when macOS could not make one.
    var bookmark: Data?
    /// Folders left out of the Indice, relative to the Secondo cervello, sorted.
    var excludedFolders: [String] = []
    /// Folders whose notes `cerca` puts first, relative to the Secondo cervello, sorted.
    var priorityFolders: [String] = []

    /// Creates the location of `folder`.
    init(folder: URL) {
        path = folder.standardizedFileURL.path
        bookmark = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Decodes a saved choice, also one saved before folders could be excluded or put first.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
        excludedFolders = try container.decodeIfPresent([String].self, forKey: .excludedFolders) ?? []
        priorityFolders = try container.decodeIfPresent([String].self, forKey: .priorityFolders) ?? []
    }

    /// The folder.
    var url: URL { URL(filePath: path, directoryHint: .isDirectory) }

    /// The name shown for the folder.
    var name: String { url.lastPathComponent }

    /// Whether the folder can be read now: `false` for a disk unplugged or a folder deleted.
    var isReachable: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Whether the folder is an Obsidian vault: it has `.obsidian/` at its root.
    var isObsidianVault: Bool {
        FileManager.default.fileExists(atPath: url.appending(path: ".obsidian").path)
    }

    /// The location after following the bookmark: the folder's new path when it was moved, itself otherwise.
    ///
    /// Never asks anything and never mounts a disk: a folder out of reach keeps its last path.
    func resolved() -> SecondBrainLocation {
        guard let bookmark else { return self }
        var isStale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                    relativeTo: nil, bookmarkDataIsStale: &isStale) else { return self }
        let path = folder.standardizedFileURL.path
        guard path != self.path || isStale else { return self }
        var moved = SecondBrainLocation(folder: folder)
        moved.excludedFolders = excludedFolders
        moved.priorityFolders = priorityFolders
        return moved
    }

    /// The path of `folder` relative to the Secondo cervello; `nil` for the folder itself or one outside it.
    func relativePath(of folder: URL) -> String? {
        let root = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let parts = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard parts.count > root.count, parts.starts(with: root) else { return nil }
        return parts.dropFirst(root.count).joined(separator: "/")
    }

    /// The folders at the top of the Secondo cervello the user can include, exclude or put first, by name:
    /// hidden folders and `Bubo/` left out.
    func topFolders() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                                     options: [.skipsHiddenFiles])) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .filter { $0 != "Bubo" }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: Saved choice

    /// The defaults key holding the chosen folder.
    static let defaultsKey = "secondBrain"

    /// Returns the folder saved in `defaults`, or `nil` when none was chosen.
    static func saved(in defaults: UserDefaults = .standard) -> SecondBrainLocation? {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(SecondBrainLocation.self, from: $0) }
    }

    /// Saves `location` in `defaults`; `nil` forgets the choice.
    static func save(_ location: SecondBrainLocation?, in defaults: UserDefaults = .standard) {
        defaults.set(location.flatMap { try? JSONEncoder().encode($0) }, forKey: defaultsKey)
    }

    // MARK: Obsidian vaults

    /// The file in which Obsidian lists its vaults. It is internal to Obsidian and undocumented: only for suggesting.
    static var obsidianConfiguration: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/obsidian/obsidian.json")
    }

    /// Returns the vaults Obsidian lists in its configuration `data` that are folders on this Mac, by name.
    ///
    /// Anything unexpected in the file yields no suggestion rather than an error.
    static func vaults(inObsidianConfiguration data: Data) -> [URL] {
        struct Configuration: Decodable {
            struct Vault: Decodable {
                var path: String
            }
            var vaults: [String: Vault]
        }
        guard let configuration = try? JSONDecoder().decode(Configuration.self, from: data) else { return [] }
        return Set(configuration.vaults.values.map(\.path))
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
            .filter { SecondBrainLocation(path: $0.path).isReachable }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// The vaults Obsidian lists on this Mac; none when Obsidian was never installed.
    static func suggestedVaults() -> [URL] {
        (try? Data(contentsOf: obsidianConfiguration)).map(vaults(inObsidianConfiguration:)) ?? []
    }

    private init(path: String) {
        self.path = path
    }
}
