import Foundation

/// The three suggestions under «Chiedi al tuo cervello»: the notes changed last, or general ones without notes.
enum HomeSuggestions {
    /// At most three suggestions: one per note in `recentNotes`, else general ones.
    static func make(recentNotes: [String]) -> [String] {
        guard !recentNotes.isEmpty else {
            return [String(localized: "Cosa ho deciso questa settimana?"),
                    String(localized: "Riassumi l'ultima Riunione"),
                    String(localized: "Cosa ricordi di me?")]
        }
        return recentNotes.prefix(3).map { String(localized: "Cosa c'è di nuovo in \($0)?") }
    }

    /// The names of the `limit` Markdown notes of `folder` changed last, Bubo's own folder and hidden files aside.
    ///
    /// - Complexity: O(n log n) in the notes of the Secondo cervello; read off the main actor.
    @concurrent
    static func recentNotes(in folder: URL, limit: Int = 3) async -> [String] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var notes: [(name: String, date: Date)] = []
        let bubo = folder.appending(path: "Bubo").standardizedFileURL.path + "/"
        while let file = files.nextObject() as? URL {
            guard file.pathExtension.lowercased() == "md", !file.standardizedFileURL.path.hasPrefix(bubo),
                  let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true
            else { continue }
            notes.append((file.deletingPathExtension().lastPathComponent, values.contentModificationDate ?? .distantPast))
        }
        return notes.sorted { $0.date > $1.date }.prefix(limit).map(\.name)
    }
}
