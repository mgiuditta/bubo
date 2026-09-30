import Testing
@testable import Bubo

struct TintaTests {
    private static let frame: Double = 1.0 / 60

    nonisolated private static let expectedBases: [(Provider, UInt32)] = [
        (.anthropic, 0xD97757), (.mistral, 0xE0A040), (.deepSeek, 0x8DB548),
        (.openAI, 0x3FAE8F), (.perplexity, 0x36A9C0), (.google, 0x4F7FE0),
        (.meta, 0x6A62DE), (.alibaba, 0x9A66DD), (.cohere, 0xD07FB0), (.xAI, 0xC8CCD4),
    ]

    private static var allTinte: [Tinta] { Provider.allCases.map(\.tinta) + [.neutral] }

    /// Runs `animation` for `seconds` of wall time, one display frame at a time.
    private static func run(_ animation: inout OrbAnimation, for seconds: Double) {
        for _ in 0..<Int((seconds / frame).rounded()) { animation.advance(by: frame) }
    }

    private static func isClose(_ lhs: Tinta, _ rhs: Tinta, tolerance: Float = 0.001) -> Bool {
        let colors = (lhs.base - rhs.base, lhs.highlight - rhs.highlight)
        let character = [lhs.spike - rhs.spike, lhs.grain - rhs.grain, lhs.bands - rhs.bands, lhs.gloss - rhs.gloss]
        return ([colors.0.x, colors.0.y, colors.0.z, colors.1.x, colors.1.y, colors.1.z] + character)
            .allSatisfy { abs($0) < tolerance }
    }

    // MARK: - Palette

    @Test(arguments: expectedBases)
    func aKnownProviderGetsItsTinta(provider: Provider, base: UInt32) {
        #expect(Tinta(for: provider).base == SIMD3(hex: base))
    }

    @Test(arguments: Provider.allCases)
    func providersAreFoundByName(provider: Provider) {
        #expect(Provider(named: provider.name.uppercased()) == provider)
    }

    @Test func anUnknownProviderGetsTheNeutralTinta() {
        #expect(Provider(named: "Unknown Labs") == nil)
        #expect(Tinta(for: Provider(named: "Unknown Labs")) == .neutral)
        #expect(Tinta.neutral.base == SIMD3(hex: 0x9C918A))
    }

    @Test func theNeutralTintaHasNoCharacter() {
        let neutral = Tinta.neutral
        #expect([neutral.spike, neutral.grain, neutral.bands, neutral.gloss] == [0, 0, 0, 0])
    }

    @Test func everyTintaIsDistinct() {
        let tinte = Self.allTinte
        for (index, tinta) in tinte.enumerated() {
            #expect(!tinte[(index + 1)...].contains(tinta))
        }
    }

    @Test(arguments: Provider.allCases)
    func noTintaSignsWithSpikesAlone(provider: Provider) {
        #expect(provider.tinta.hasCharacterBeyondSpikes)
    }

    @Test func xAIStandsApartFromTheNeutralTintaBeyondItsSpikes() {
        let xAI = Tinta.xAI, neutral = Tinta.neutral
        func luminance(_ color: SIMD3<Float>) -> Float { (color * SIMD3(0.2126, 0.7152, 0.0722)).sum() }
        #expect(luminance(xAI.base) - luminance(neutral.base) > 0.15)
        #expect(xAI.base.z > xAI.base.x, "xAI is a cold silver")
        #expect(neutral.base.x > neutral.base.z, "the neutral Tinta is a warm grey")
        #expect(xAI.gloss > 0.8)
        #expect(xAI.grain > 0)
        #expect(xAI.spike > 0)
    }

    // MARK: - Interpolation

    @Test func mixingAtTheEndsGivesEachTinta() {
        #expect(Self.isClose(Tinta.google.mixed(with: .xAI, by: 0), .google))
        #expect(Self.isClose(Tinta.google.mixed(with: .xAI, by: 1), .xAI))
    }

    @Test func mixingHalfwayAveragesEveryComponent() {
        let halfway = Tinta.google.mixed(with: .xAI, by: 0.5)
        var expected = Tinta.google
        expected.base = (Tinta.google.base + Tinta.xAI.base) / 2
        expected.highlight = (Tinta.google.highlight + Tinta.xAI.highlight) / 2
        expected.spike = (Tinta.google.spike + Tinta.xAI.spike) / 2
        expected.grain = (Tinta.google.grain + Tinta.xAI.grain) / 2
        expected.bands = (Tinta.google.bands + Tinta.xAI.bands) / 2
        expected.gloss = (Tinta.google.gloss + Tinta.xAI.gloss) / 2
        #expect(Self.isClose(halfway, expected))
    }

    // MARK: - Transition

    @Test func theOrbTurnsHalfwayAtHalfTimeAndArrivesAfterOnePointTwoSeconds() {
        var animation = OrbAnimation(tinta: .anthropic)
        animation.targetTinta = .openAI
        Self.run(&animation, for: 0.6)
        #expect(Self.isClose(animation.tinta, Tinta.anthropic.mixed(with: .openAI, by: 0.5)))
        Self.run(&animation, for: 0.6)
        #expect(Self.isClose(animation.tinta, .openAI))
    }

    @Test func theTurnEasesInWithSmoothstep() {
        var animation = OrbAnimation(tinta: .anthropic)
        animation.targetTinta = .openAI
        Self.run(&animation, for: 0.3)
        // smoothstep(0.25) = 0.15625, slower than linear at the start.
        #expect(Self.isClose(animation.tinta, Tinta.anthropic.mixed(with: .openAI, by: 0.15625)))
    }

    @Test func withReduceMotionTheTintaCrossFadesInPointFourSeconds() {
        var animation = OrbAnimation(tinta: .anthropic)
        animation.reducesMotion = true
        animation.targetTinta = .openAI
        Self.run(&animation, for: 0.2)
        #expect(Self.isClose(animation.tinta, Tinta.anthropic.mixed(with: .openAI, by: 0.5)))
        Self.run(&animation, for: 0.2)
        #expect(Self.isClose(animation.tinta, .openAI))
    }

    @Test func aNewProviderMidwayTurnsFromWhereTheTintaIs() {
        var animation = OrbAnimation(tinta: .anthropic)
        animation.targetTinta = .openAI
        Self.run(&animation, for: 0.6)
        let midway = animation.tinta
        animation.targetTinta = .google
        animation.advance(by: Self.frame)
        #expect(Self.isClose(animation.tinta, midway, tolerance: 0.01))
    }

    // MARK: - Uniforms

    @Test func theShaderTakesItsColorFromTheTinta() {
        var animation = OrbAnimation(tinta: .perplexity)
        animation.state = .working
        Self.run(&animation, for: 3)
        var uniforms = OrbUniforms()
        uniforms.apply(animation)
        #expect(uniforms.base == Tinta.perplexity.base)
        #expect(uniforms.highlight == Tinta.perplexity.highlight)
        #expect(uniforms.grain == Tinta.perplexity.grain)
        #expect(uniforms.gloss == Tinta.perplexity.gloss)
        #expect(abs(uniforms.spike - (OrbState.working.motion.spike + Tinta.perplexity.spike)) < 0.01)
    }
}
