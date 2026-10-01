import Foundation

/// The folder the user chose as Secondo cervello: its path, and a bookmark to follow it when it is moved.
///
/// Bubo is not sandboxed, so the bookmark grants nothing: it only finds the folder again under a new name.
nonisolated struct SecondBrainLocation: Codable, Equatable, Sendable {
    /// The folder's path when it was last found.
    var path: String
    /// A bookmark to the folder; `nil` when macOS could not make one.
    var bookmark: Data?

    /// Creates the location of `folder`.
    init(folder: URL) {
        path = folder.standardizedFileURL.path
        bookmark = try? folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
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
        return SecondBrainLocation(folder: folder)
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
