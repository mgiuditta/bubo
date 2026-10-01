import Foundation
import OSLog

/// The MetricKit reports kept on this Mac, in `Application Support/Bubo/Diagnostica/`, for 30 days.
///
/// Only files: nothing here, or in `MetricsCollector`, ever opens a connection.
nonisolated struct DiagnosticsStore: Sendable {
    /// How long a report is kept.
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    /// The folder of the reports.
    let folder: URL

    private var latestDayFile: URL {
        folder.appending(path: "ultimo-giorno.json")
    }

    /// The store in Bubo's Application Support folder.
    static func makeDefault() throws -> DiagnosticsStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return DiagnosticsStore(folder: support.appending(path: "Bubo/Diagnostica", directoryHint: .isDirectory))
    }

    /// Saves the JSON of a metric payload and, when its day is the latest, its summary; then drops expired reports.
    func saveMetrics(_ json: Data, summary: DailyMetrics, now: Date = .now) throws {
        try save(json, named: "metriche", endingAt: summary.end)
        if latestDay().map({ $0.end <= summary.end }) ?? true {
            try JSONEncoder().encode(summary).write(to: latestDayFile, options: .atomic)
        }
        removeExpiredReports(now: now)
    }

    /// Saves the JSON of a diagnostic payload (crashes, hangs, CPU and disk exceptions); then drops expired reports.
    func saveDiagnostics(_ json: Data, endingAt end: Date, now: Date = .now) throws {
        try save(json, named: "diagnosi", endingAt: end)
        removeExpiredReports(now: now)
    }

    /// The summary of the latest day saved; `nil` when there is none.
    func latestDay() -> DailyMetrics? {
        do {
            return try JSONDecoder().decode(DailyMetrics.self, from: Data(contentsOf: latestDayFile))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            Logger.diagnostics.error("Ultimo giorno unreadable: \(error)")
            return nil
        }
    }

    /// Whether at least one report is saved.
    var hasReports: Bool {
        !reports().isEmpty
    }

    /// Deletes the reports last written more than `retention` before `now`.
    func removeExpiredReports(now: Date = .now) {
        let oldest = now.addingTimeInterval(-Self.retention)
        for report in reports() {
            let written = (try? report.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let written, written < oldest else { continue }
            do {
                try FileManager.default.removeItem(at: report)
            } catch {
                Logger.diagnostics.error("Expired report not deleted: \(error)")
            }
        }
    }

    private func save(_ json: Data, named kind: String, endingAt end: Date) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = end.formatted(Date.ISO8601FormatStyle(timeSeparator: .omitted))
        try json.write(to: folder.appending(path: "\(kind)-\(stamp).json"), options: .atomic)
    }

    private func reports() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                 options: .skipsHiddenFiles)
        return (files ?? []).filter { $0.pathExtension == "json" }
    }
}

extension Logger {
    nonisolated static let diagnostics = Logger(subsystem: "com.mgiuditta.bubo", category: "diagnostics")
}
