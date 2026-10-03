import AVFoundation
import CryptoKit
import Foundation
import os

/// A file that becomes a Riunione: audio and video are transcribed on the Mac, trascrizioni only cleaned.
nonisolated enum MeetingImportFile {
    /// What a file holds, by its extension.
    enum Kind: Equatable, Sendable {
        /// m4a, mp3, wav.
        case audio
        /// mp4, mov: only the audio is transcribed.
        case video
        /// vtt, srt: sentences with their time.
        case subtitles
        /// txt: sentences without time.
        case text
    }

    /// The kind of the file at `url`; `nil` when it cannot become a Riunione.
    static func kind(of url: URL) -> Kind? {
        switch url.pathExtension.lowercased() {
        case "m4a", "mp3", "wav": .audio
        case "mp4", "mov": .video
        case "vtt", "srt": .subtitles
        case "txt": .text
        default: nil
        }
    }

    /// Whether a drop of `urls` asks for Riunioni rather than Allegati: only audio, video and subtitles, as a `.txt`
    /// or a folder more often goes to Claude.
    static func isMeetingDrop(_ urls: [URL]) -> Bool {
        !urls.isEmpty && urls.allSatisfy { url in
            url.isFileURL && !url.hasDirectoryPath && [.audio, .video, .subtitles].contains(kind(of: url))
        }
    }

    /// The files of `urls` that can become a Riunione, folders opened with their subfolders, sorted by path.
    static func files(in urls: [URL]) -> [URL] {
        var files: [URL] = []
        for url in urls {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isFolder else {
                if kind(of: url) != nil { files.append(url) }
                continue
            }
            let contents = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let file = contents?.nextObject() as? URL {
                if kind(of: file) != nil { files.append(file) }
            }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// The SHA-256 of the bytes of the file at `url`, in hexadecimal, read a megabyte at a time.
    ///
    /// - Throws: A file system error when the file cannot be read.
    static func fingerprint(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The day of the file at `url`: the earlier of its creation and its last change, since a copy keeps the second.
    static func date(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return [values?.creationDate, values?.contentModificationDate].compactMap(\.self).min() ?? .now
    }

    /// The fingerprints of the Riunioni already imported in `folder`, read from their `impronta` property.
    static func fingerprints(inNotesAt folder: URL) -> Set<String> {
        let notes = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var fingerprints: Set<String> = []
        for note in notes where note.pathExtension == "md" {
            guard let text = try? String(contentsOf: note, encoding: .utf8) else { continue }
            let properties = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(30)
            if let line = properties.first(where: { $0.hasPrefix("impronta: ") }) {
                fingerprints.insert(String(line.dropFirst("impronta: ".count)).trimmingCharacters(in: .whitespaces))
            }
        }
        return fingerprints
    }

    /// The text of the trascrizione at `url`, in UTF-8 or, failing that, Windows Latin 1, without the byte order mark.
    ///
    /// - Throws: ``MeetingFailure/fileUnreadable`` when the file cannot be read.
    static func text(of url: URL) throws(MeetingFailure) -> String {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
        else { throw .fileUnreadable }
        return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    /// The sentences of a WebVTT or SubRip trascrizione with their time, and when the last one ends.
    ///
    /// Cleaning leaves out headers, notes, styles, cue numbers and settings, and tags; a voice tag `<v Anna>` becomes
    /// `Anna: `; a sentence repeated by the next cue, as automatic captions do, is kept once.
    static func lines(ofSubtitles text: String) -> (lines: [MeetingLine], end: Duration?) {
        var lines: [MeetingLine] = []
        var end: Duration?
        let blocks = text.replacing("\r\n", with: "\n").replacing("\r", with: "\n").split(separator: "\n\n")
        for block in blocks {
            let rows = block.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let timing = rows.firstIndex(where: { $0.contains("-->") }) else { continue }
            let times = rows[timing].components(separatedBy: "-->").map {
                time(from: $0.trimmingCharacters(in: .whitespaces).prefix { !$0.isWhitespace })
            }
            guard let start = times.first ?? nil else { continue }
            end = max(end ?? .zero, (times.last ?? nil) ?? start)
            let sentence = cleaned(rows[(timing + 1)...].joined(separator: " "))
            guard !sentence.isEmpty, sentence != lines.last?.text else { continue }
            lines.append(MeetingLine(speaker: nil, start: start, text: sentence))
        }
        return (lines, end)
    }

    /// The sentences of a plain trascrizione, one per non-empty line, a line repeated right after kept once.
    static func lines(ofText text: String) -> [MeetingLine] {
        var lines: [MeetingLine] = []
        for row in text.split(whereSeparator: \.isNewline) {
            let sentence = cleaned(String(row))
            guard !sentence.isEmpty, sentence != lines.last?.text else { continue }
            lines.append(MeetingLine(speaker: nil, start: nil, text: sentence))
        }
        return lines
    }

    /// The audio of the video at `url`, written as an m4a file in a new temporary folder.
    ///
    /// - Throws: ``MeetingFailure/fileUnreadable`` when the video has no audio or cannot be read.
    static func audio(ofVideo url: URL) async throws(MeetingFailure) -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let audio = folder.appending(path: "audio.m4a")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: AVAssetExportPresetAppleM4A)
            else { throw MeetingFailure.fileUnreadable }
            try await session.export(to: audio, as: .m4a)
            return audio
        } catch {
            Logger.meetings.error("Video audio not exported: \(String(describing: error), privacy: .public)")
            try? FileManager.default.removeItem(at: folder)
            throw .fileUnreadable
        }
    }

    /// How long the audio or video at `url` lasts; `nil` when it cannot be read.
    static func duration(of url: URL) async -> Duration? {
        guard let time = try? await AVURLAsset(url: url).load(.duration), time.isNumeric else { return nil }
        return .seconds(time.seconds)
    }

    /// The time of a cue, as `01:02:03.456`, `02:03.456` or `01:02:03,456`; `nil` when malformed.
    private static func time(from text: Substring) -> Duration? {
        let parts = text.replacing(",", with: ".").split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let value = Double(part) else { return nil }
            seconds = seconds * 60 + value
        }
        return .milliseconds(Int((seconds * 1000).rounded()))
    }

    /// `text` with its voice tags as `Name: `, without other tags nor the common entities, its spaces collapsed.
    private static func cleaned(_ text: String) -> String {
        text.replacing(#/<v(?:\.[^ >]*)?\s+([^>]+)>/#) { "\($0.output.1): " }
            .replacing(#/<[^>]*>/#, with: "")
            .replacing("&amp;", with: "&").replacing("&lt;", with: "<").replacing("&gt;", with: ">")
            .replacing("&nbsp;", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
