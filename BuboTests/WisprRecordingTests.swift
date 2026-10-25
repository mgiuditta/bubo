import Foundation
import Testing
@testable import Bubo

/// Following Wispr Flow's raw files as they grow, in a fake meetings folder.
struct WisprRecordingTests {
    let meetings: URL
    let folder: URL

    init() throws {
        meetings = URL.temporaryDirectory.appending(path: "wispr-\(UUID().uuidString)", directoryHint: .isDirectory)
        folder = meetings.appending(path: "riunione", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["mic.pcm", "system.pcm"] {
            try Data(repeating: 0, count: 3200).write(to: folder.appending(path: name))
        }
    }

    private func append(_ samples: [Int16], to name: String) throws {
        let handle = try FileHandle(forWritingTo: folder.appending(path: name))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: samples.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    @Test func readsOnlyWhatWasWrittenAfterItStarted() throws {
        let recording = WisprRecording(folder: folder)
        #expect(recording.newAudio().isEmpty)
        try append([1, 2, 3], to: "mic.pcm")
        let audio = recording.newAudio()
        let mine = try #require(audio.first { $0.speaker == .me })
        #expect(audio.count == 1)
        #expect(mine.buffer.frameLength == 3)
        #expect(mine.buffer.int16ChannelData?[0][2] == 3)
        #expect(recording.newAudio().isEmpty)
    }

    @Test func waitsForTheSecondHalfOfASample() throws {
        let recording = WisprRecording(folder: folder)
        let handle = try FileHandle(forWritingTo: folder.appending(path: "system.pcm"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0x05, 0x00, 0x07]))
        #expect(recording.newAudio().first?.buffer.frameLength == 1)
        try handle.write(contentsOf: Data([0x00]))
        try handle.close()
        let others = try #require(recording.newAudio().first { $0.speaker == .others })
        #expect(others.buffer.int16ChannelData?[0][0] == 7)
    }

    @Test func findsTheRecordingInProgress() {
        #expect(WisprRecording.current(in: meetings)?.lastPathComponent == folder.lastPathComponent)
        #expect(WisprRecording.current(in: meetings, at: .now + 60) == nil)
    }
}
