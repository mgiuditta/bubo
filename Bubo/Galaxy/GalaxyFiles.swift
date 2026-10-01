import Foundation

/// The files of a Progetto that the Galassia shows: those git knows and does not ignore, or, outside git, those of the
/// folder without hidden files and build caches (spec 11).
nonisolated enum GalaxyFiles {
    /// The folders a scan outside git never enters, by name.
    static let excludedFolders: Set<String> = Set(WorktreeManager.excludedByDefault.compactMap { path in
        let name = path.hasSuffix("/") ? String(path.dropLast()) : path
        return name.contains("/") ? nil : name
    }).union(["node_modules", "Pods", ".git"])

    /// The most files a scan outside git collects, so a Progetto as large as a home folder cannot stall Bubo.
    static let scanLimit = 200_000

    /// The paths, relative to `project` and in name order, of the Progetto's files.
    ///
    /// Inside git: tracked files and untracked ones not ignored, from `git ls-files`. Outside git, or when git fails:
    /// a scan of the folder.
    @concurrent
    static func list(in project: URL, runner: ProcessRunner = .live) async -> [String] {
        let arguments = ["-C", project.path, "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
        if let output = try? await runner.run(URL(filePath: "/usr/bin/git"), arguments), output.exitCode == 0 {
            return Array(Set(output.standardOutput.split(separator: "\0").map(String.init))).sorted()
        }
        return scan(project)
    }

    /// The files under `folder`, relative to it and in name order, skipping hidden files and ``excludedFolders``.
    static func scan(_ folder: URL) -> [String] {
        // Relative paths straight from the walk: no prefix to strip, so no trouble with /private/var and the like.
        guard let walker = FileManager.default.enumerator(atPath: folder.path) else { return [] }
        var files: [String] = []
        while let path = walker.nextObject() as? String {
            let name = (path as NSString).lastPathComponent
            let isFolder = walker.fileAttributes?[.type] as? FileAttributeType == .typeDirectory
            if name.hasPrefix(".") || isFolder && excludedFolders.contains(name) {
                if isFolder { walker.skipDescendants() }
                continue
            }
            guard !isFolder else { continue }
            files.append(path)
            if files.count >= scanLimit { break }
        }
        return files.sorted()
    }
}
