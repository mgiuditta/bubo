import Foundation

/// The files of one `claude` Sessione that a Consegna carries: the transcript, its subagent and the tool results
/// kept apart, each by its file name.
nonisolated struct SessionFiles: Equatable, Sendable {
    /// `<sessionId>.jsonl`: one JSON object per line.
    var transcript: String
    /// `subagents/agent-<id>.jsonl`, by file name.
    var subagents: [String: String] = [:]
    /// `subagents/agent-<id>.meta.json`, by file name.
    var subagentMetadata: [String: String] = [:]
    /// `tool-results/<id>.txt`, by file name: the outputs too long to stay in the transcript.
    var toolResults: [String: String] = [:]

    /// The name the transcript has in the files a scan or a failure points to.
    static let transcriptName = "transcript.jsonl"

    /// Every JSONL file, the transcript first, then the subagent by name.
    var jsonlFiles: [(name: String, content: String)] {
        [(Self.transcriptName, transcript)] + subagents.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Reads the Sessione `sessionID` from the project folder `claude` wrote it in.
    ///
    /// - Throws: When the transcript cannot be read; missing subagent and tool results are no Sessione's fault.
    init(sessionID: String, in projectFolder: URL) throws {
        transcript = try String(contentsOf: projectFolder.appending(path: "\(sessionID).jsonl"), encoding: .utf8)
        let folder = projectFolder.appending(path: sessionID, directoryHint: .isDirectory)
        for file in Self.files(in: folder.appending(path: "subagents", directoryHint: .isDirectory)) {
            let name = file.lastPathComponent
            let content = try String(contentsOf: file, encoding: .utf8)
            if name.hasSuffix(".jsonl") {
                subagents[name] = content
            } else if name.hasSuffix(".meta.json") {
                subagentMetadata[name] = content
            }
        }
        for file in Self.files(in: folder.appending(path: "tool-results", directoryHint: .isDirectory)) {
            toolResults[file.lastPathComponent] = try String(contentsOf: file, encoding: .utf8)
        }
    }

    /// Creates the files of a Sessione from their content.
    init(transcript: String, subagents: [String: String] = [:], subagentMetadata: [String: String] = [:],
         toolResults: [String: String] = [:]) {
        self.transcript = transcript
        self.subagents = subagents
        self.subagentMetadata = subagentMetadata
        self.toolResults = toolResults
    }

    private static func files(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }
}
