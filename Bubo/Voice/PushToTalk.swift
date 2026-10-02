import Foundation
import OSLog

/// The global shortcut as push-to-talk (spec 08): a tap shows or hides the HUD; held past `holdThreshold` it opens the
/// Ascolto, with the Orb following the voice and the partial text in the prompt, and at release the final text goes
/// into the pipeline of the ingressi.
@Observable
final class PushToTalk {
    /// How long the shortcut stays down before a tap becomes push-to-talk.
    static let holdThreshold: Duration = .milliseconds(300)

    /// Whether the Ascolto is open: from the hold until the final text.
    private(set) var isListening = false
    /// Why the last hold could not listen; `nil` after a hold that could.
    private(set) var failure: VoiceFailure?

    /// Creates push-to-talk on `listener`.
    ///
    /// - Parameters:
    ///   - microphone: The microphone permission, asked at the first hold, never at launch.
    ///   - orb: The Orb that listens.
    ///   - holdThreshold: How long the shortcut stays down before it is a hold.
    ///   - interrupt: Runs as the shortcut goes down, before the microphone opens: stops Bubo's voice, so the hold
    ///     reopens the Ascolto and the microphone does not hear it.
    ///   - tap: Runs on a tap: shows or hides the HUD.
    ///   - show: Runs when the Ascolto opens: brings the prompt to the front.
    ///   - dictate: Gets the text heard so far, then the final text with `isFinal`, which sends it.
    init(listener: any VoiceListener, microphone: MicrophoneAccess = .system, orb: OrbControls = .shared,
         holdThreshold: Duration = PushToTalk.holdThreshold, interrupt: @escaping () -> Void = {}, tap: @escaping () -> Void, show: @escaping () -> Void,
         dictate: @escaping (_ text: String, _ isFinal: Bool) -> Void) {
        self.listener = listener
        self.microphone = microphone
        self.orb = orb
        self.threshold = holdThreshold
        self.interrupt = interrupt
        self.tap = tap
        self.show = show
        self.dictate = dictate
    }

    @ObservationIgnored private let listener: any VoiceListener
    @ObservationIgnored private let microphone: MicrophoneAccess
    @ObservationIgnored private let orb: OrbControls
    @ObservationIgnored private let threshold: Duration
    @ObservationIgnored private let interrupt: () -> Void
    @ObservationIgnored private let tap: () -> Void
    @ObservationIgnored private let show: () -> Void
    @ObservationIgnored private let dictate: (String, Bool) -> Void
    /// Whether the shortcut is down.
    @ObservationIgnored private var isHeld = false
    /// Whether the shortcut stayed down past the threshold since it went down.
    @ObservationIgnored private var isHold = false
    /// The wait for the threshold, then the opening of the Ascolto.
    @ObservationIgnored private(set) var holding: Task<Void, Never>?
    /// The microphone opening: `nil` once it listens, otherwise why it could not.
    @ObservationIgnored private var starting: Task<VoiceFailure?, Never>?
    /// The last close of the microphone, with or without the final text; a new opening waits for it.
    @ObservationIgnored private(set) var closing: Task<Void, Never>?

    /// Hides the line of the last failure.
    func dismissFailure() {
        failure = nil
    }

    /// The shortcut went down: Bubo stops speaking, and with the microphone already granted it opens at once, so the
    /// first word is not lost.
    func press() {
        guard !isHeld else { return }
        interrupt()
        isHeld = true
        isHold = false
        if microphone.status() == .granted { openMicrophone() }
        holding = Task {
            try? await Task.sleep(for: threshold)
            guard !Task.isCancelled, isHeld else { return }
            await beginListening()
        }
    }

    /// The shortcut was let go: a tap shows or hides the HUD, a hold sends what was heard.
    func release() {
        guard isHeld else { return }
        isHeld = false
        guard isHold else {
            holding?.cancel()
            closeMicrophone(sending: false)
            tap()
            return
        }
        // Still asking for the microphone or opening it: `beginListening` sees the release and gives up.
        if isListening { closeMicrophone(sending: true) }
    }

    private func beginListening() async {
        isHold = true
        switch microphone.status() {
        case .denied:
            failure = .microphoneDenied
            show()
            return
        case .undetermined:
            // The first hold asks; the user lets go while answering, so the next hold listens.
            guard await microphone.request() else {
                failure = .microphoneDenied
                show()
                return
            }
            guard isHeld else { return }
            openMicrophone()
        case .granted:
            break
        }
        failure = nil
        isListening = true
        orb.questionState = .listening
        show()
        if let failure = await starting?.value {
            self.failure = failure
            if isListening { endListening() }
        }
    }

    private func openMicrophone() {
        let previous = closing
        starting = Task { [weak self, listener] in
            await previous?.value
            do throws(VoiceFailure) {
                try await listener.start(partial: { [weak self] in self?.heard($0) },
                                         level: { [weak self] in self?.heardLevel($0) })
                return nil
            } catch {
                Logger.voice.notice("Not listening: \(String(describing: error), privacy: .public)")
                return error
            }
        }
    }

    /// Closes the microphone once it is open, and with `sending` hands on the final text.
    private func closeMicrophone(sending: Bool) {
        guard let opening = starting else { return }
        starting = nil
        closing = Task {
            guard await opening.value == nil else { return }
            guard sending else {
                await listener.cancel()
                return
            }
            let interval = Signposts.beginInterval(.voiceFinalText)
            let text = await listener.finish()
            Signposts.endInterval(.voiceFinalText, interval)
            endListening()
            guard !text.isEmpty else { return }
            dictate(text, true)
        }
    }

    private func endListening() {
        isListening = false
        orb.voiceLevel = nil
        if orb.questionState == .listening { orb.questionState = nil }
    }

    private func heard(_ text: String) {
        guard isListening else { return }
        dictate(text, false)
    }

    private func heardLevel(_ level: Float) {
        guard isListening else { return }
        orb.voiceLevel = level
    }
}

extension Logger {
    nonisolated static let voice = Logger(subsystem: "com.mgiuditta.bubo", category: "voice")
}
