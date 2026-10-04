import Foundation
@testable import Bubo

/// The fake Sessione of the Consegna tests (spec 24): a transcript with subagent, MCP, compaction and tool results,
/// written by `claude` 2.1.287's rules, with planted secrets. No real data: sender, paths and secrets are made up.
nonisolated struct DeliveryCorpus: Decodable, Sendable {
    struct Sender: Decodable, Sendable {
        var worktree: String
        var home: String
        var email: String
        var organizzazione: String
        var idOrganizzazione: String
        var sessionId: String
    }

    struct Question: Decodable, Sendable {
        var domanda: String
        var risposta: String
    }

    var mittente: Sender
    /// Rule id → planted secret, broken with `§`.
    var segreti: [String: String]
    /// What no scanner is expected to find → the secret.
    var mancati: [String: String]
    var domande: [Question]

    static let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/Consegna")

    static let shared: DeliveryCorpus = {
        let data = (try? Data(contentsOf: folder.appending(path: "consegna-segreti.json"))) ?? Data()
        return (try? JSONDecoder().decode(DeliveryCorpus.self, from: data))
            ?? DeliveryCorpus(mittente: Sender(worktree: "", home: "", email: "", organizzazione: "", idOrganizzazione: "",
                                               sessionId: ""), segreti: [:], mancati: [:], domande: [])
    }()

    /// The planted secrets, whole again, by rule id.
    var secrets: [String: String] { segreti.mapValues(PlantedSecrets.joined) }

    /// The secrets no scanner is expected to find, whole again.
    var missed: [String] { mancati.values.map(PlantedSecrets.joined) }

    /// The Sessione's files, with the secrets whole again.
    static func session() throws -> SessionFiles {
        func read(_ name: String) throws -> String {
            PlantedSecrets.joined(try String(contentsOf: folder.appending(path: name), encoding: .utf8))
        }
        return SessionFiles(
            transcript: try read("consegna-transcript.jsonl"),
            subagents: ["agent-a1.jsonl": try read("agent-a1.jsonl")],
            subagentMetadata: ["agent-a1.meta.json": try read("agent-a1.meta.json")],
            toolResults: ["toolu_big.txt": try read("toolu_big.txt")]
        )
    }

    /// The sender of the fake Sessione, as the cleaner needs it.
    var sender: TranscriptCleaner.Sender {
        TranscriptCleaner.Sender(worktree: mittente.worktree, home: mittente.home,
                                 identity: [mittente.email, mittente.organizzazione, mittente.idOrganizzazione])
    }
}

extension SessionFiles {
    /// Every file's text, by name.
    var allTexts: [(name: String, text: String)] {
        jsonlFiles.map { ($0.name, $0.content) }
            + subagentMetadata.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
            + toolResults.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}
