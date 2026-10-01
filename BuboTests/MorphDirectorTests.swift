import Testing
@testable import Bubo

struct MorphDirectorTests {
    private static let morph = MorphDirector.morphDuration
    private static let hold = MorphDirector.minimumHold
    private static let lente = variante("lente", categoria: .ricerca)
    private static let busta = variante("busta", categoria: .mail)

    private static func variante(_ nome: String, categoria: Categoria) -> Variante {
        Variante(nome: nome, forma: nome, categoria: categoria, descrizione: "", parole: [])
    }

    /// A Regia resting on `variante` at time 10, its hold over.
    private static func resting(on variante: Variante?) -> MorphDirector {
        var director = MorphDirector()
        director.request(variante, at: 0)
        director.advance(to: 10)
        return director
    }

    /// The frame `director` would draw at `time`, leaving `director` untouched.
    private static func frame(of director: MorphDirector, at time: Double) -> MorphFrame {
        var director = director
        director.advance(to: time)
        return director.frame
    }

    private static func still(on variante: Variante?) -> MorphFrame {
        MorphFrame(from: variante, to: variante, progress: 1, opacity: 1)
    }

    @Test func durationsAreNamedConstants() {
        #expect(MorphDirector.morphDuration == 1.1)
        #expect(MorphDirector.minimumHold == 1.5)
        #expect(MorphDirector.returnDelay == 5)
        #expect(MorphDirector.fadeDuration == 0.4)
    }

    // MARK: - Always through the Blob, 1.1 s per Morph, smoothstep

    @Test func blobToVarianteTakesTheWholeMorph() {
        var director = MorphDirector()
        director.request(Self.lente, at: 0)

        #expect(Self.frame(of: director, at: 0) == MorphFrame(from: nil, to: Self.lente, progress: 0, opacity: 1))
        let halfway = Self.frame(of: director, at: Self.morph / 2)
        #expect(halfway.progress == 0.5 && halfway.morph == 0.5 && halfway.forma == .lente)
        #expect(Self.frame(of: director, at: Self.morph - 0.01).morph < 1)
        director.advance(to: Self.morph)
        #expect(director.frame == Self.still(on: Self.lente))
        #expect(director.frame.morph == 1)
    }

    @Test func varianteToBlobTakesTheWholeMorph() {
        var director = Self.resting(on: Self.lente)
        director.request(nil, at: 10)

        let halfway = Self.frame(of: director, at: 10 + Self.morph / 2)
        #expect(halfway.from == Self.lente && halfway.to == nil)
        #expect(halfway.forma == .lente && halfway.morph == 0.5)
        #expect(Self.frame(of: director, at: 10 + Self.morph) == Self.still(on: nil))
    }

    @Test func varianteToVarianteGoesThroughTheBlobInTwoHalfLegs() {
        var director = Self.resting(on: Self.lente)
        director.request(Self.busta, at: 10)

        let firstLeg = Self.frame(of: director, at: 10 + Self.morph / 4)
        #expect(firstLeg.from == Self.lente && firstLeg.to == nil && firstLeg.progress == 0.5)
        let secondLeg = Self.frame(of: director, at: 10 + Self.morph * 3 / 4)
        #expect(secondLeg.from == nil && secondLeg.to == Self.busta && secondLeg.progress == 0.5)
        #expect(Self.frame(of: director, at: 10 + Self.morph + 0.001) == Self.still(on: Self.busta))
    }

    @Test func progressIsEasedWithSmoothstep() {
        var director = MorphDirector()
        director.request(Self.lente, at: 0)
        for linear in [0.1, 0.25, 0.8] {
            let expected = Float(linear * linear * (3 - 2 * linear))
            #expect(abs(Self.frame(of: director, at: Self.morph * linear).progress - expected) < 0.0001)
        }
    }

    // MARK: - Minimum hold on a Variante

    @Test func staysOnAVarianteForTheMinimumHold() {
        var director = MorphDirector()
        director.request(Self.lente, at: 0)
        director.advance(to: 0.2)
        director.request(Self.busta, at: 0.2)

        let arrival = Self.morph
        #expect(Self.frame(of: director, at: arrival + Self.hold - 0.01) == Self.still(on: Self.lente))
        let leaving = Self.frame(of: director, at: arrival + Self.hold + Self.morph / 4)
        #expect(leaving.from == Self.lente && leaving.to == nil && leaving.progress == 0.5)
    }

    @Test func theBlobHasNoHold() {
        var director = Self.resting(on: Self.lente)
        director.request(nil, at: 10)
        director.advance(to: 10.5)
        director.request(Self.busta, at: 10.5)

        let leaving = Self.frame(of: director, at: 10 + Self.morph * 1.5)
        #expect(leaving.from == nil && leaving.to == Self.busta && leaving.progress == 0.5)
    }

    // MARK: - Only the latest request waits; a started leg reaches its end

    @Test func aStartedLegRunsToItsEnd() {
        var director = MorphDirector()
        director.request(Self.lente, at: 0)
        director.advance(to: 0.5)
        director.request(nil, at: 0.5)

        let frame = Self.frame(of: director, at: 0.9)
        #expect(frame.from == nil && frame.to == Self.lente && frame.progress > 0.5)
        #expect(Self.frame(of: director, at: Self.morph) == Self.still(on: Self.lente))
    }

    @Test func onlyTheLatestRequestWaits() {
        var director = Self.resting(on: nil)
        director.request(Self.lente, at: 10)
        director.advance(to: 10.3)
        director.request(Self.busta, at: 10.3)
        director.request(nil, at: 10.4)
        director.request(Self.busta, at: 10.5)
        #expect(director.destination == Self.busta)

        let arrival = 10 + Self.morph
        #expect(Self.frame(of: director, at: arrival + Self.hold + Self.morph + 0.001) == Self.still(on: Self.busta))
    }

    @Test func aRequestForTheArrivingVarianteDropsTheWaitingOne() {
        var director = Self.resting(on: nil)
        director.request(Self.lente, at: 10)
        director.advance(to: 10.3)
        director.request(Self.busta, at: 10.3)
        director.request(Self.lente, at: 10.4)
        #expect(Self.frame(of: director, at: 30) == Self.still(on: Self.lente))
    }

    @Test func aNewerRequestReplacesTheSecondLegNotYetStarted() {
        var director = Self.resting(on: Self.lente)
        director.request(Self.busta, at: 10)
        director.advance(to: 10.2)
        director.request(nil, at: 10.2)

        // The first leg still reaches the Blob; the Orb then stays there instead of going on to busta.
        #expect(Self.frame(of: director, at: 10.4).to == nil)
        #expect(Self.frame(of: director, at: 30) == Self.still(on: nil))
    }

    // MARK: - Back to the Blob 5 s into Riposo

    @Test func returnsToTheBlobFiveSecondsIntoRiposo() {
        var director = Self.resting(on: Self.lente)
        director.enter(.speaking, at: 10)
        director.enter(.idle, at: 11)

        let due = 11 + MorphDirector.returnDelay
        #expect(Self.frame(of: director, at: due - 0.01) == Self.still(on: Self.lente))
        let returning = Self.frame(of: director, at: due + Self.morph / 2)
        #expect(returning.from == Self.lente && returning.to == nil && returning.progress == 0.5)
        #expect(Self.frame(of: director, at: due + Self.morph) == Self.still(on: nil))
    }

    @Test func aNewVarianteCancelsTheReturn() {
        var director = Self.resting(on: Self.lente)
        director.enter(.speaking, at: 10)
        director.enter(.idle, at: 11)
        director.advance(to: 13)
        director.request(Self.busta, at: 13)
        #expect(Self.frame(of: director, at: 40) == Self.still(on: Self.busta))
    }

    @Test func leavingRiposoCancelsTheReturn() {
        var director = Self.resting(on: Self.lente)
        director.enter(.speaking, at: 10)
        director.enter(.idle, at: 11)
        director.enter(.listening, at: 12)
        #expect(Self.frame(of: director, at: 40) == Self.still(on: Self.lente))
    }

    // MARK: - The Stato never changes the Forma

    @Test(arguments: OrbState.allCases.filter { $0 != .idle })
    func aStatoKeepsTheVariante(state: OrbState) {
        var director = Self.resting(on: Self.lente)
        director.enter(state, at: 10)
        #expect(director.destination == Self.lente)
        #expect(Self.frame(of: director, at: 60) == Self.still(on: Self.lente))
    }

    // MARK: - Reduce Motion

    @Test func reduceMotionFadesInsteadOfMorphing() {
        var director = Self.resting(on: Self.lente)
        director.reducesMotion = true
        director.request(Self.busta, at: 10)
        let fade = MorphDirector.fadeDuration

        let fadingOut = Self.frame(of: director, at: 10 + fade / 4)
        #expect(fadingOut == MorphFrame(from: Self.lente, to: Self.lente, progress: 1, opacity: 0.5))
        let fadingIn = Self.frame(of: director, at: 10 + fade * 3 / 4)
        #expect(fadingIn == MorphFrame(from: Self.busta, to: Self.busta, progress: 1, opacity: 0.5))
        #expect(Self.frame(of: director, at: 10 + fade) == Self.still(on: Self.busta))
    }

    @Test func reduceMotionNeverDeforms() {
        var director = MorphDirector()
        director.reducesMotion = true
        director.request(Self.lente, at: 0)
        for tick in 0...40 {
            let frame = Self.frame(of: director, at: Double(tick) * 0.01)
            #expect(frame.morph == 0 || frame.morph == 1)
        }
    }

    @Test func reduceMotionAlsoSlowsTheOrbsOwnMotion() {
        var animation = OrbAnimation()
        animation.reducesMotion = true
        animation.advance(by: 0.04)
        #expect(animation.time < 0.04)
    }

    // MARK: - Frame

    @Test func aVarianteWithoutAFormaDrawsTheBlob() {
        let drago = Variante(nome: "drago", forma: "drago", categoria: .creativo, descrizione: "", parole: [])
        #expect(Self.still(on: drago).forma == .blob)
        #expect(Self.still(on: Self.lente).forma == .lente)
        #expect(Self.still(on: nil).morph == 0)
    }
}
