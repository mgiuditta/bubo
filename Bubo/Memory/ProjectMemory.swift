import Foundation
import os

/// The auto memory of a Progetto as it is on disk now: the `MEMORY.md` index and one file per memory (spec 13).
///
/// Claude Code writes it in `~/.claude/projects/<repo>/memory/`, shared by every worktree of the repo. Bubo keeps
/// no copy: each read goes to the disk, and Bubo writes there only when the user edits or deletes a memory.
nonisolated struct ProjectMemory: Equatable, Sendable {
    /// The `MEMORY.md` index, which Claude Code loads at the start of every conversation up to its limits.
    struct Index: Equatable, Sendable {
        let text: String
        /// The lines of the file, as Claude Code counts them against ``ProjectMemory/lineLimit``.
        var lineCount: Int { text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count }
        /// The size of the file in bytes, counted against ``ProjectMemory/byteLimit``.
        var byteCount: Int { text.utf8.count }

        /// How full the index is, as the larger of its lines and bytes over their limits: past 1, Claude Code
        /// loads only the first part.
        var fill: Double {
            max(Double(lineCount) / Double(ProjectMemory.lineLimit), Double(byteCount) / Double(ProjectMemory.byteLimit))
        }

        /// Whether the index is past 80% of a limit, where Claude Code too starts asking to shorten it.
        var isNearLimit: Bool { fill >= ProjectMemory.warningFill }
    }

    /// A memory: one Markdown file next to the index, with its kind and the date of its last write in the frontmatter.
    struct Topic: Equatable, Sendable, Identifiable {
        /// The file name, such as `feedback_testing.md`.
        let name: String
        let text: String
        /// The `name` of the frontmatter, if any.
        let title: String?
        /// The `description` of the frontmatter, if any.
        let summary: String?
        /// `user`, `feedback`, `project` or `reference`, as Claude Code writes it.
        let kind: String?
        /// When Claude Code last wrote the file (`modified`), or else when the file last changed on disk.
        let modified: Date?

        var id: String { name }
    }

    /// The folder of the memory, which may not exist yet.
    let directory: URL
    /// The index; `nil` while Claude has not written one.
    let index: Index?
    /// The memories, most recent first.
    let topics: [Topic]

    /// The lines of `MEMORY.md` that Claude Code loads.
    static let lineLimit = 200
    /// The bytes of `MEMORY.md` that Claude Code loads.
    static let byteLimit = 25_000
    /// The fill past which Bubo, like Claude Code, warns that the index is near its limit.
    static let warningFill = 0.8
    /// The name of the index in the folder.
    static let indexName = "MEMORY.md"

    /// Whether the folder holds nothing yet.
    var isEmpty: Bool { index == nil && topics.isEmpty }

    // MARK: Finding the folder

    /// The memory folder of the Progetto at `project`: `<home>/.claude/projects/<repo>/memory`.
    ///
    /// The `<repo>` name comes from the main checkout of the repo, so every worktree shares it, and is never read
    /// back from the folder names: Claude Code encodes the path with loss.
    static func directory(ofProject project: URL,
                          home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: ".claude/projects", directoryHint: .isDirectory)
            .appending(path: folderName(ofRoot: TrustGate.root(of: project)), directoryHint: .isDirectory)
            .appending(path: "memory", directoryHint: .isDirectory)
    }

    /// The name Claude Code gives the project folder of `root`: every UTF-16 unit that is not an ASCII letter or digit
    /// becomes `-`; past 200 characters, the first 200 and a hash of the whole path in base 36.
    static func folderName(ofRoot root: String) -> String {
        let units = Array(root.utf16)
        let name = String(units.map { unit in
            let isAlphanumeric = (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit)
            return isAlphanumeric ? Character(Unicode.Scalar(UInt8(unit))) : "-"
        })
        guard name.count > 200 else { return name }
        // The 32-bit `hash * 31 + unit` of the CLI's JavaScript, made positive.
        let hash = units.reduce(Int32(0)) { hash, unit in hash &* 31 &+ Int32(unit) }
        return "\(name.prefix(200))-\(String(hash.magnitude, radix: 36))"
    }

    // MARK: Reading

    /// Reads the memory in `directory` from the disk, away from the main actor.
    @concurrent static func reading(in directory: URL) async -> ProjectMemory {
        read(in: directory)
    }

    /// Reads the memory in `directory` from the disk; a folder that does not exist yet is an empty memory.
    static func read(in directory: URL) -> ProjectMemory {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        let index = try? String(contentsOf: directory.appending(path: indexName), encoding: .utf8)
        let topics = names
            .filter { $0.hasSuffix(".md") && $0 != indexName && !$0.hasPrefix(".") }
            .compactMap { name -> Topic? in
                let file = directory.appending(path: name)
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                let changed = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return topic(named: name, text: text, changedOnDisk: changed)
            }
            .sorted { ($0.modified ?? .distantPast, $1.name) > ($1.modified ?? .distantPast, $0.name) }
        return ProjectMemory(directory: directory, index: index.map(Index.init(text:)), topics: topics)
    }

    /// The memory in the file `name` with contents `text`, from its frontmatter.
    static func topic(named name: String, text: String, changedOnDisk: Date? = nil) -> Topic {
        let fields = frontmatter(of: text)
        let modified = fields["modified"].flatMap { try? Date($0, strategy: .iso8601) }
            ?? fields["modified"].flatMap { try? Date($0, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
        return Topic(name: name, text: text, title: fields["name"], summary: fields["description"],
                     kind: fields["type"], modified: modified ?? changedOnDisk)
    }

    /// The `key: value` lines of the YAML frontmatter at the top of `text`, without quotes.
    static func frontmatter(of text: String) -> [String: String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return [:] }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty, !value.isEmpty { fields[key] = value }
        }
        return fields
    }

    // MARK: Changing

    /// The index without the lines that point to the memory `name`, as `[…](name)`.
    func index(removing name: String) -> String? {
        guard let index else { return nil }
        return index.text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("(\(name))") }
            .joined(separator: "\n")
    }
}

/// Why Bubo did not change a memory file.
nonisolated enum ProjectMemoryError: Error, Equatable {
    /// The file changed on disk after Bubo read it: the user sees it again before changing it.
    case changedOnDisk
}

extension ProjectMemory {
    /// Replaces the file `name` with `text`, if it still holds `expected`; a `nil` text deletes it.
    ///
    /// The write is atomic, so Claude Code never reads half a file.
    ///
    /// - Throws: ``ProjectMemoryError/changedOnDisk`` when the file is no longer `expected`, or a file error.
    static func write(_ text: String?, to name: String, in directory: URL, expecting expected: String?) throws {
        let file = directory.appending(path: name)
        let current = try? String(contentsOf: file, encoding: .utf8)
        guard current == expected else { throw ProjectMemoryError.changedOnDisk }
        if let text {
            try Data(text.utf8).write(to: file, options: .atomic)
        } else {
            try FileManager.default.removeItem(at: file)
        }
        Logger.memory.notice("Memory file \(text == nil ? "deleted" : "written", privacy: .public) by the user")
    }

    /// Deletes the memory `topic` and its lines in the index, if neither changed on disk since this read.
    ///
    /// - Throws: ``ProjectMemoryError/changedOnDisk`` before touching anything, or a file error.
    func delete(_ topic: Topic) throws {
        let current = try? String(contentsOf: directory.appending(path: Self.indexName), encoding: .utf8)
        guard current == index?.text else { throw ProjectMemoryError.changedOnDisk }
        try Self.write(nil, to: topic.name, in: directory, expecting: topic.text)
        if let index, let trimmed = self.index(removing: topic.name), trimmed != index.text {
            try Self.write(trimmed, to: Self.indexName, in: directory, expecting: index.text)
        }
    }
}

extension Logger {
    nonisolated static let memory = Logger(subsystem: "com.mgiuditta.bubo", category: "memory")
}
