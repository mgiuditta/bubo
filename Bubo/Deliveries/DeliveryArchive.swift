import AppleArchive
import Foundation
import System

/// The content of a Consegna before it is encrypted: an Apple Archive with LZFSE compression (spec 24).
///
/// Only type, path, data and mode of each file go in: no owner, no dates, nothing about the sender's Mac.
nonisolated enum DeliveryArchive {
    /// The archive did not write or read.
    struct Failure: Error, Equatable {}

    /// Archives everything inside `folder` into a new file at `file`.
    ///
    /// - Throws: ``Failure`` when a stream does not open, or an error of Apple Archive.
    static func archive(_ folder: URL, to file: URL) throws {
        guard let output = ArchiveByteStream.fileStream(path: FilePath(file.path), mode: .writeOnly,
                                                       options: [.create, .truncate],
                                                       permissions: FilePermissions(rawValue: 0o600))
        else { throw Failure() }
        guard let compression = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: output) else {
            try? output.close()
            throw Failure()
        }
        guard let encoder = ArchiveStream.encodeStream(writingTo: compression),
              let keys = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,MOD")
        else {
            try? compression.close()
            try? output.close()
            throw Failure()
        }
        do {
            try encoder.writeDirectoryContents(archiveFrom: FilePath(folder.path), keySet: keys)
        } catch {
            try? encoder.close()
            try? compression.close()
            try? output.close()
            throw error
        }
        // In this order: each close flushes into the next stream.
        try encoder.close()
        try compression.close()
        try output.close()
    }

    /// Extracts the archive at `file` into the existing folder `folder`.
    ///
    /// - Throws: ``Failure`` when a stream does not open, or an error of Apple Archive.
    static func extract(_ file: URL, to folder: URL) throws {
        guard let input = ArchiveByteStream.fileStream(path: FilePath(file.path), mode: .readOnly, options: [],
                                                      permissions: FilePermissions(rawValue: 0o600))
        else { throw Failure() }
        defer { try? input.close() }
        guard let decompression = ArchiveByteStream.decompressionStream(readingFrom: input) else { throw Failure() }
        defer { try? decompression.close() }
        guard let decoder = ArchiveStream.decodeStream(readingFrom: decompression) else { throw Failure() }
        defer { try? decoder.close() }
        guard let extractor = ArchiveStream.extractStream(extractingTo: FilePath(folder.path),
                                                          flags: [.ignoreOperationNotPermitted])
        else { throw Failure() }
        defer { try? extractor.close() }
        _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
    }
}
