import Testing
@testable import Bubo

@MainActor
struct PushToTalkTests {
    /// A listener that hears what the test says, with no microphone.
    final class FakeListener: VoiceListener {
        var failure: VoiceFailure?
        var finalText = ""
        private(set) var starts = 0
        private(set) var finishes = 0
        private(set) var cancels = 0
        private var partial: ((String) -> Void)?
        private var level: ((Float) -> Void)?

        func start(partial: @escaping (String) -> Void, level: @escaping (Float) -> Void) async throws(VoiceFailure) {
            starts += 1
            if let failure { throw failure }
            self.partial = partial
            self.level = level
        }

        func finish() async -> String {
            finishes += 1
            return finalText
        }

        func cancel() async {
            cancels += 1
        }

        func say(_ text: String, level value: Float = 0.5) {
            partial?(text)
            level?(value)
        }
    }

    /// What push-to-talk did with the HUD and the prompt.
    final class Recorder {
        var taps = 0
        var interrupts = 0
        var shows = 0
        var dictated: [(text: String, isFinal: Bool)] = []
    }

    let listener = FakeListener()
    let recorder = Recorder()
    let orb = OrbControls()

    func pushToTalk(microphone: MicrophoneAccess.Status = .granted, grants: Bool = true,
                    holdThreshold: Duration = .zero) -> PushToTalk {
        var status = microphone
        let access = MicrophoneAccess {
            status
        } request: {
            status = grants ? .granted : .denied
            return grants
        }
        return PushToTalk(listener: listener, microphone: access, orb: orb, holdThreshold: holdThreshold) {
            recorder.interrupts += 1
        } tap: {
            recorder.taps += 1
        } show: {
            recorder.shows += 1
        } dictate: {
            recorder.dictated.append(($0, $1))
        }
    }

    @Test func aTapTogglesTheHUDAndDropsTheMicrophone() async {
        let voice = pushToTalk(holdThreshold: .seconds(60))
        voice.press()
        voice.release()
        await voice.holding?.value
        await voice.closing?.value
        #expect(recorder.taps == 1)
        #expect(recorder.dictated.isEmpty)
        #expect(listener.cancels == 1)
        #expect(listener.finishes == 0)
        #expect(orb.questionState == nil)
    }

    @Test func aHoldListensAndSendsTheFinalTextAtRelease() async {
        let voice = pushToTalk()
        voice.press()
        await voice.holding?.value
        #expect(voice.isListening)
        #expect(orb.questionState == .listening)
        #expect(recorder.shows == 1)

        listener.say("ciao", level: 0.4)
        #expect(orb.voiceLevel == 0.4)
        listener.finalText = "ciao Bubo"
        voice.release()
        await voice.closing?.value

        #expect(recorder.taps == 0)
        #expect(recorder.dictated.map(\.text) == ["ciao", "ciao Bubo"])
        #expect(recorder.dictated.map(\.isFinal) == [false, true])
        #expect(!voice.isListening)
        #expect(orb.voiceLevel == nil)
        #expect(orb.questionState == nil)
    }

    @Test func nothingHeardSendsNothing() async {
        let voice = pushToTalk()
        voice.press()
        await voice.holding?.value
        voice.release()
        await voice.closing?.value
        #expect(recorder.dictated.isEmpty)
        #expect(orb.questionState == nil)
    }

    @Test func aDeniedMicrophoneLeavesTheOrbAtRestWithTheLine() async {
        let voice = pushToTalk(microphone: .denied)
        voice.press()
        await voice.holding?.value
        voice.release()
        #expect(voice.failure == .microphoneDenied)
        #expect(!voice.isListening)
        #expect(orb.questionState == nil)
        #expect(listener.starts == 0)
        #expect(recorder.taps == 0)
    }

    @Test func theFirstHoldAsksForTheMicrophone() async {
        let voice = pushToTalk(microphone: .undetermined)
        voice.press()
        // Not asked on the press: a tap never asks.
        #expect(listener.starts == 0)
        await voice.holding?.value
        #expect(voice.isListening)
        #expect(listener.starts == 1)
    }

    @Test func refusingTheMicrophoneShowsTheLine() async {
        let voice = pushToTalk(microphone: .undetermined, grants: false)
        voice.press()
        await voice.holding?.value
        #expect(voice.failure == .microphoneDenied)
        #expect(orb.questionState == nil)
    }

    @Test func aListenerThatCannotStartEndsTheAscolto() async {
        listener.failure = .modelDownloading
        let voice = pushToTalk()
        voice.press()
        await voice.holding?.value
        #expect(voice.failure == .modelDownloading)
        #expect(!voice.isListening)
        #expect(orb.questionState == nil)
        voice.dismissFailure()
        #expect(voice.failure == nil)
    }

    @Test func aRepeatedPressIsIgnored() async {
        let voice = pushToTalk(holdThreshold: .seconds(60))
        voice.press()
        voice.press()
        voice.release()
        await voice.closing?.value
        #expect(listener.starts == 1)
        #expect(recorder.taps == 1)
        #expect(recorder.interrupts == 1)
    }

    @Test func thePressStopsTheVoiceBeforeTheAscolto() async {
        let voice = pushToTalk()
        voice.press()
        // At once, not after the threshold: the audio stops within 100 ms.
        #expect(recorder.interrupts == 1)
        #expect(!voice.isListening)
        await voice.holding?.value
        #expect(voice.isListening)
        #expect(orb.questionState == .listening)
    }
}
