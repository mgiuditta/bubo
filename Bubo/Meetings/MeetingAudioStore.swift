import Foundation
import os

/// The audio of the Riunioni, one folder per recording with a track per speaker, in `Application Support/Bubo/Riunioni`.
nonisolated struct MeetingAudioStore: Sendable {
    /// How long the audio stays with ``MeetingAudioRetention/thirtyDays``.
    static let keptFor: Duration = .seconds(30 * 24 * 60 * 60)

    /// The folder holding the recordings.
    let folder: URL

    /// Creates the store in `folder`.
    init(folder: URL) {
        self.folder = folder
    }

    /// The store in Application Support.
    ///
    /// - Throws: When Application Support cannot be found.
    static func makeDefault() throws -> MeetingAudioStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return MeetingAudioStore(folder: support.appending(path: "Bubo/Riunioni", directoryHint: .isDirectory))
    }

    /// Creates the folder of a new recording.
    ///
    /// - Throws: A file system error when it cannot be created.
    func makeRecordingFolder() throws -> URL {
        let recording = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: recording, withIntermediateDirectories: true)
        return recording
    }

    /// Deletes the recording in `recording`.
    func remove(_ recording: URL) {
        do {
            try FileManager.default.removeItem(at: recording)
        } catch {
            Logger.meetings.error("Riunione audio not deleted: \(error)")
        }
    }

    /// Deletes the recordings created more than ``keptFor`` before `now`.
    func removeExpired(now: Date = .now) {
        let recordings = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let limit = now.addingTimeInterval(-TimeInterval(Self.keptFor.components.seconds))
        for recording in recordings {
            guard let created = try? recording.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  created < limit else { continue }
            remove(recording)
        }
    }
}

extension Logger {
    nonisolated static let meetings = Logger(subsystem: "com.mgiuditta.bubo", category: "meetings")
}
