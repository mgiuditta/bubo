import AVFoundation

/// Whether Bubo may open the microphone, and how it asks the first time.
struct MicrophoneAccess {
    /// What the user decided about the microphone.
    enum Status {
        case undetermined, denied, granted
    }

    /// The decision as it stands now.
    var status: () -> Status
    /// Asks the user, once; returns whether the microphone was granted.
    var request: () async -> Bool

    /// The microphone permission of macOS (TCC).
    static var system: MicrophoneAccess {
        MicrophoneAccess {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .granted
            case .notDetermined: .undetermined
            default: .denied
            }
        } request: {
            await AVCaptureDevice.requestAccess(for: .audio)
        }
    }

    /// The pane of System Settings where the user gives Bubo the microphone back.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
}
