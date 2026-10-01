import Foundation
import os

/// The last files seen in each Progetto, kept in Bubo's Caches folder so the next opening draws at once, before the
/// files are listed again (spec 11).
///
/// The layout is a function of the files alone, so the cache keeps the files and lays them out again: on 10,000 files
/// that is faster than decoding a saved layout.
nonisolated struct GalaxyCache: Sendable {
    /// The folder of the saved lists.
    var folder: URL

    /// The cache in Bubo's Caches folder.
    static let standard = GalaxyCache(folder: URL.cachesDirectory.appending(path: "com.mgiuditta.bubo/Galassia",
                                                                            directoryHint: .isDirectory))

    /// The files last saved for `project`; `nil` when there are none.
    func files(of project: URL) -> [String]? {
        guard let data = try? Data(contentsOf: file(for: project)) else { return nil }
        return String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
    }

    /// Saves `files` for `project`, replacing the previous list.
    func save(_ files: [String], of project: URL) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(files.joined(separator: "\0").utf8).write(to: file(for: project), options: .atomic)
        } catch {
            Logger.galaxy.error("Galassia: cache not saved: \(error)")
        }
    }

    private func file(for project: URL) -> URL {
        let key = GalaxyLayout.fnv1a(project.standardizedFileURL.path)
        return folder.appending(path: String(key, radix: 16))
    }
}

extension Logger {
    nonisolated static let galaxy = Logger(subsystem: "com.mgiuditta.bubo", category: "galaxy")
}
