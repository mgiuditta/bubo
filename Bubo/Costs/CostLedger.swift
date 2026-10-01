import Foundation
import os

/// Bubo's local record of every turn, one entry per turn, kept in a JSON file across launches.
///
/// Idempotent: a turn read again, while it streams or after a crash, replaces its entry instead of adding one.
@Observable
final class CostLedger {
    /// One turn of a Sessione, with its Progetto.
    struct Entry: Codable, Equatable, Identifiable, Sendable {
        /// The turn: the id Bubo gave the agent's conversation.
        let id: String
        var session: UUID
        var project: URL
        /// When the turn last reported, so a turn across midnight counts on the day it ends.
        var date: Date
        var usage: TurnUsage
    }

    /// The figure of several turns in one unit.
    struct Amount: Equatable, Sendable {
        /// In US dollars.
        var value: Decimal = 0
        /// Whether a turn was priced at a guessed rate (`costBasis: unknown`).
        var isUncertain = false
        /// Whether a turn stopped without a valid `result`, so `value` misses its figure.
        var isIncomplete = false

        mutating func add(_ usage: TurnUsage) {
            value += usage.cost ?? 0
            isUncertain = isUncertain || usage.basis == .unknown
            isIncomplete = isIncomplete || usage.cost == nil || !usage.isComplete
        }
    }

    /// The turns, oldest first.
    private(set) var entries: [Entry] = []

    /// Creates a ledger kept in `file`; with `nil`, in memory only.
    init(file: URL? = nil) {
        self.file = file
        guard let file else { return }
        do {
            entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))
        } catch CocoaError.fileReadNoSuchFile {
        } catch {
            Logger.costs.error("Costi unreadable: \(error)")
        }
    }

    @ObservationIgnored private let file: URL?

    /// The ledger in Bubo's Application Support folder.
    static func makeDefault() throws -> CostLedger {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return CostLedger(file: support.appending(path: "Bubo/Costi.json"))
    }

    /// Records `usage` as the turn `turn` of the Sessione `session` on `project`, replacing what the turn reported before.
    func record(_ usage: TurnUsage, turn: String, session: UUID, project: URL, at date: Date = .now) {
        let entry = Entry(id: turn, session: session, project: project, date: date, usage: usage)
        if let index = entries.firstIndex(where: { $0.id == turn }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        save()
    }

    /// The total of the Sessione `session`, one amount per unit it has turns in.
    func total(of session: UUID) -> [CostUnit: Amount] {
        entries.filter { $0.session == session }.reduce(into: [:]) { total, entry in
            total[entry.usage.unit, default: Amount()].add(entry.usage)
        }
    }

    /// The latest turn of the Sessione `session`.
    func lastTurn(of session: UUID) -> Entry? {
        entries.last { $0.session == session }
    }

    private func save() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        } catch {
            Logger.costs.error("Costi not saved: \(error)")
        }
    }
}

extension Logger {
    nonisolated static let costs = Logger(subsystem: "com.mgiuditta.bubo", category: "costs")
}
