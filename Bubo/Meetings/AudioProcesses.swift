import AudioToolbox
import CoreAudio

/// The processes Core Audio knows, read to tap the audio of one app and to find where the Mac plays.
nonisolated enum AudioProcesses {
    /// The Core Audio objects of the app `bundleID` and of its helpers, such as a browser's tab processes.
    static func objects(ofApp bundleID: String) -> [AudioObjectID] {
        let processes: [AudioObjectID] = array(of: kAudioHardwarePropertyProcessObjectList,
                                               in: AudioObjectID(kAudioObjectSystemObject))
        return processes.filter { process in
            string(of: kAudioProcessPropertyBundleID, in: process).map { belongs($0, to: bundleID) } ?? false
        }
    }

    /// Whether the process `processBundleID` is the app `appBundleID` or one of its helpers, named after it.
    static func belongs(_ processBundleID: String, to appBundleID: String) -> Bool {
        processBundleID == appBundleID || processBundleID.hasPrefix(appBundleID + ".")
    }

    /// The UID of the device the Mac plays to; `nil` when there is none.
    static func defaultOutputUID() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = address(of: kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size,
                                         &device) == noErr else { return nil }
        return string(of: kAudioDevicePropertyDeviceUID, in: device)
    }

    /// The global address of `selector`.
    static func address(of selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// The array of object IDs `selector` holds in `object`; empty when it cannot be read.
    private static func array(of selector: AudioObjectPropertySelector, in object: AudioObjectID) -> [AudioObjectID] {
        var address = address(of: selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown),
                                      count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    /// The string `selector` holds in `object`; `nil` when it cannot be read.
    private static func string(of selector: AudioObjectPropertySelector, in object: AudioObjectID) -> String? {
        var address = address(of: selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        // Core Audio hands over a string the caller owns.
        return value?.takeRetainedValue() as String?
    }
}
