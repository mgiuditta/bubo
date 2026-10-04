import Testing
@testable import Bubo

struct OrbAnimationTests {
    private static let frame: Double = 1.0 / 60

    @Test func everyStateHasItsOwnMotion() {
        let motions = OrbState.allCases.map(\.motion)
        for (index, motion) in motions.enumerated() {
            #expect(!motions[(index + 1)...].contains(motion))
        }
    }

    @Test func startsAtRestWithTheIdleMotion() {
        let animation = OrbAnimation()
        #expect(animation.state == .idle)
        #expect(animation.motion == OrbState.idle.motion)
    }

    @Test(arguments: OrbState.allCases.filter { $0 != .idle })
    func oneFrameAfterAChangeTheMotionIsBetweenTheTwoStates(state: OrbState) {
        var animation = OrbAnimation()
        animation.state = state
        animation.advance(by: Self.frame)

        let idle = OrbState.idle.motion, target = state.motion
        for component in OrbMotion.components {
            let value = animation.motion[keyPath: component]
            let low = min(idle[keyPath: component], target[keyPath: component])
            let high = max(idle[keyPath: component], target[keyPath: component])
            #expect(low <= value && value <= high)
            if low != high { #expect(value != target[keyPath: component]) }
        }
    }

    @Test func aLongPauseDoesNotJumpToTheNewState() {
        var animation = OrbAnimation()
        animation.state = .thinking
        animation.advance(by: 10)
        #expect(animation.motion.swirl < OrbState.thinking.motion.swirl / 2)
    }

    @Test(arguments: OrbState.allCases)
    func settlesOnTheStateWithinThreeSeconds(state: OrbState) {
        var animation = OrbAnimation()
        animation.state = state
        for _ in 0..<180 { animation.advance(by: Self.frame) }
        for component in OrbMotion.components {
            #expect(abs(animation.motion[keyPath: component] - state.motion[keyPath: component]) < 0.01)
        }
    }

    @Test(arguments: OrbState.allCases)
    func onlyListeningAndSpeakingMoveWithTheVoice(state: OrbState) {
        var animation = OrbAnimation()
        animation.state = state
        var loudest: Float = 0
        for _ in 0..<120 {
            animation.advance(by: Self.frame)
            loudest = max(loudest, animation.audio)
        }
        #expect((loudest > 0.1) == [.listening, .speaking].contains(state))
    }

    @Test(arguments: [OrbState.listening, .speaking])
    func theRippleFollowsTheVoiceLevel(in state: OrbState) {
        var animation = OrbAnimation()
        animation.state = state
        animation.voiceLevel = 0.6
        for _ in 0..<120 { animation.advance(by: Self.frame) }
        #expect(abs(animation.audio - 0.6) < 0.01)
        animation.voiceLevel = 0
        for _ in 0..<120 { animation.advance(by: Self.frame) }
        #expect(animation.audio < 0.01)
    }

    @Test func reduceMotionSlowsTheClock() {
        var animation = OrbAnimation()
        animation.reducesMotion = true
        animation.advance(by: 0.04)
        #expect(abs(animation.time - 0.04 * 0.35) < 0.0001)
    }

    @Test func clockAdvancesByAtMostOneLongFrame() {
        var animation = OrbAnimation()
        animation.advance(by: 3)
        #expect(animation.time == Float(OrbAnimation.longestStep))
    }

    /// A Float clock that only grows loses its steps within hours of frames: the Orb stutters, then stops.
    @Test func clockKeepsEvenStepsAcrossItsTurn() {
        var animation = OrbAnimation()
        let step = OrbAnimation.longestStep
        let steps = Int(OrbAnimation.clockSpan * 1.5 / step)
        var previous = animation.time
        for _ in 0..<steps {
            animation.advance(by: step)
            let moved = abs(animation.time - previous)
            #expect(moved > Float(step) * 0.98 || abs(Double(animation.time) - OrbAnimation.clockSpan) < step)
            #expect(moved <= Float(step) * 1.02)
            previous = animation.time
        }
        #expect(abs(Double(animation.time) - OrbAnimation.clockSpan * 0.5) < 0.01)
    }
}
