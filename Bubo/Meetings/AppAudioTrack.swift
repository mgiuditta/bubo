import AVFoundation
import AudioToolbox
import CoreAudio
import os

/// Writes the audio one app plays to a file, with a Core Audio process tap: no bot in the call, no other app's sound.
///
/// The app keeps playing as usual: the tap only listens. macOS asks the user the first time.
final class AppAudioTrack {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var procedure: AudioDeviceIOProcID?

    /// Creates the track, not recording yet.
    init() {}

    /// Starts writing the audio of `processes` to an AAC file at `url`.
    ///
    /// - Throws: ``MeetingFailure/appAudioDenied`` when macOS refuses the tap or the file cannot be created.
    func start(processes: [AudioObjectID], writingTo url: URL) throws(MeetingFailure) {
        let description = CATapDescription(monoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        // A helper that ends and starts again, as a browser's tab, comes back into the tap.
        description.isProcessRestoreEnabled = true
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { return try fail("Process tap not created", status: status) }
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioProcesses.address(of: kAudioTapPropertyFormat)
        status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format)
        guard status == noErr, let audioFormat = AVAudioFormat(streamDescription: &format),
              let output = AudioProcesses.defaultOutputUID() else {
            return try fail("Tap format not read", status: status)
        }
        let device: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Bubo Riunione",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        status = AudioHardwareCreateAggregateDevice(device as CFDictionary, &aggregate)
        guard status == noErr else { return try fail("Aggregate device not created", status: status) }
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: url, settings: MeetingAudioFormat.settings(for: audioFormat),
                                   commonFormat: audioFormat.commonFormat, interleaved: audioFormat.isInterleaved)
        } catch {
            return try fail("Track file not created: \(error)", status: noErr)
        }
        status = AudioDeviceCreateIOProcIDWithBlock(&procedure, aggregate, Self.queue,
                                                    Self.writer(of: audioFormat, into: file))
        guard status == noErr else { return try fail("IO procedure not created", status: status) }
        status = AudioDeviceStart(aggregate, procedure)
        guard status == noErr else { return try fail("Aggregate device not started", status: status) }
    }

    /// Stops listening and closes the file.
    func stop() {
        if aggregate != kAudioObjectUnknown {
            AudioDeviceStop(aggregate, procedure)
            // Releasing the block releases the file, which closes it.
            if let procedure { AudioDeviceDestroyIOProcID(aggregate, procedure) }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        procedure = nil
        aggregate = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
    }

    /// Logs `message`, undoes what was created and throws.
    private func fail(_ message: String, status: OSStatus) throws(MeetingFailure) {
        Logger.meetings.error("\(message, privacy: .public) (\(status))")
        stop()
        throw .appAudioDenied
    }

    /// The queue the tap's audio arrives on, off the main thread.
    private static let queue = DispatchQueue(label: "com.mgiuditta.bubo.meeting-tap", qos: .userInitiated)

    /// The block that writes each buffer of the tap to `file`, run on ``queue``.
    nonisolated private static func writer(of format: AVAudioFormat, into file: AVAudioFile) -> AudioDeviceIOBlock {
        { _, input, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil) else { return }
            do {
                try file.write(from: buffer)
            } catch {
                Logger.meetings.error("Tap buffer not written: \(error)")
            }
        }
    }
}
