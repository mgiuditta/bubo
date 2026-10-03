import FluidAudio
import Foundation
import os

/// Tells apart the voices of a Riunione's «Altri» track on the Mac: who spoke and when.
///
/// The models are pyannote's Community-1 converted to Core ML by FluidAudio (CC-BY-4.0: pyannote, WeSpeaker,
/// BUT Speech@FIT, Fluid Inference), about 22 MB downloaded from Hugging Face on first use into
/// `Application Support/Bubo/Modelli`, never in the bundle; the audio never leaves the Mac.
nonisolated enum MeetingDiarizer {
    /// A stretch of the track said by one voice.
    struct Turn: Equatable, Sendable {
        /// The voice, as the model names it: equal for the same voice, meaningless otherwise.
        var speaker: String
        var start: Duration
        var end: Duration
    }

    /// The turns of the track at `url`; empty when the models cannot be downloaded or the analysis fails, and the
    /// lines then keep «Altri».
    @concurrent
    static func turns(in url: URL) async -> [Turn] {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
            let manager = OfflineDiarizerManager()
            try await manager.prepareModels(directory: support.appending(path: "Bubo/Modelli", directoryHint: .isDirectory))
            return try await manager.process(url).segments.map {
                Turn(speaker: $0.speakerId, start: .seconds(Double($0.startTimeSeconds)),
                     end: .seconds(Double($0.endTimeSeconds)))
            }
        } catch {
            Logger.meetings.error("Voices not told apart: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// `lines` with the voice of the turn they overlap most, or else the nearest, as «Parlante 1», «Parlante 2»…
    /// in the order the voices first speak; unchanged without turns.
    ///
    /// - Parameter lines: The sentences of one track, in the order they were said.
    static func lines(_ lines: [MeetingLine], attributedTo turns: [Turn]) -> [MeetingLine] {
        guard !turns.isEmpty else { return lines }
        var numbers: [String: Int] = [:]
        return lines.map { line in
            let turn = turns.max { fit(of: line, in: $0) < fit(of: line, in: $1) }!
            let number = numbers[turn.speaker] ?? numbers.count + 1
            numbers[turn.speaker] = number
            var line = line
            line.speaker = .participant(number)
            return line
        }
    }

    /// How well `line` falls in `turn`: first by how long they overlap, then by how close they are.
    private static func fit(of line: MeetingLine, in turn: Turn) -> (Duration, Duration) {
        let start = line.start ?? .zero
        let end = start + line.length
        let overlap = min(end, turn.end) - max(start, turn.start)
        let distance = max(turn.start - end, start - turn.end, .zero)
        return (max(overlap, .zero), .zero - distance)
    }
}
