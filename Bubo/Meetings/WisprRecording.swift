import AVFoundation
import Foundation

/// A recording Wispr Flow is making, read as it grows: while it records a meeting, Wispr Flow writes the microphone and
/// the audio of the call to two raw files in its folder, which the Suggeritore follows as `tail -f` does.
///
/// The files are Wispr Flow's own, not a documented interface: a new version may change them.
final class WisprRecording {
    /// The folder of the recording.
    let folder: URL
    private var tracks: [(speaker: MeetingLine.Speaker, file: URL, offset: UInt64)]

    /// Follows the recording in `folder` from now on: what was said before is not read.
    init(folder: URL) {
        self.folder = folder
        let files: [(MeetingLine.Speaker, URL)] = [(.me, folder.appending(path: "mic.pcm")),
                                                   (.others, folder.appending(path: "system.pcm"))]
        tracks = files.map { speaker, file in (speaker, file, Self.size(of: file)) }
    }

    /// The audio written since the last call, for each speaker whose file grew.
    func newAudio() -> [(speaker: MeetingLine.Speaker, buffer: AVAudioPCMBuffer)] {
        tracks.indices.compactMap { index in
            let track = tracks[index]
            guard let handle = try? FileHandle(forReadingFrom: track.file) else { return nil }
            defer { try? handle.close() }
            guard (try? handle.seek(toOffset: track.offset)) != nil, let data = try? handle.readToEnd() else { return nil }
            // Whole samples only: half of one waits for the next call.
            let samples = data.count / 2
            guard samples > 0, let buffer = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: AVAudioFrameCount(samples)),
                  let channel = buffer.int16ChannelData?[0] else { return nil }
            data.withUnsafeBytes { bytes in
                for sample in 0..<samples { channel[sample] = Int16(littleEndian: bytes.load(fromByteOffset: sample * 2, as: Int16.self)) }
            }
            buffer.frameLength = AVAudioFrameCount(samples)
            tracks[index].offset += UInt64(samples * 2)
            return (track.speaker, buffer)
        }
    }

    /// The folder of the recording Wispr Flow is making: the one whose microphone file grew in the last
    /// ``liveWindow``; `nil` when Wispr Flow is not recording.
    static func current(in meetings: URL = meetings, at time: Date = .now) -> URL? {
        let folders = (try? FileManager.default.contentsOfDirectory(at: meetings, includingPropertiesForKeys: nil)) ?? []
        let live = folders.compactMap { folder -> (URL, Date)? in
            let values = try? folder.appending(path: "mic.pcm").resourceValues(forKeys: [.contentModificationDateKey])
            guard let changed = values?.contentModificationDate, time.timeIntervalSince(changed) < liveWindow else { return nil }
            return (folder, changed)
        }
        return live.max { $0.1 < $1.1 }?.0
    }

    private static func size(of file: URL) -> UInt64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64) ?? 0
        return size / 2 * 2
    }

    /// Where Wispr Flow keeps its meetings.
    static let meetings = URL.homeDirectory.appending(path: "Library/Application Support/Wispr Flow/meetings",
                                                      directoryHint: .isDirectory)
    /// The format of both files, measured: 16 kHz, 16-bit, mono, at 32 000 bytes a second.
    static let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
    /// How recently the microphone file must have grown for the recording to be in progress.
    static let liveWindow: TimeInterval = 30
}
