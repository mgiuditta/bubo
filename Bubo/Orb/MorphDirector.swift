/// The Regia del Morph: which Variante the Orb shows, and how it turns from one Forma into the next.
///
/// A pure state machine with time as an input, so the renderer drives it frame by frame and tests drive it by hand.
/// Every Morph goes through the Blob; Variante requests that arrive faster than the Orb can follow keep only the latest;
/// the Stato never changes the Forma, except that 5 s into Riposo the Orb goes back to the Blob.
nonisolated struct MorphDirector {
    /// How long a whole Morph lasts; Variante → Variante splits it into two legs through the Blob.
    static let morphDuration: Double = 1.1
    /// The least time the Orb stays on a Variante before the next Morph starts.
    static let minimumHold: Double = 1.5
    /// How long after entering Riposo the Orb goes back to the Blob.
    static let returnDelay: Double = 5
    /// How long the fade that replaces the Morph lasts with Reduce Motion on.
    static let fadeDuration: Double = 0.4

    /// Whether new changes of Forma fade instead of morphing; a change already under way keeps its style.
    var reducesMotion = false

    /// The Variante the Orb rests on, or the one the current leg started from; `nil` is the Blob.
    private(set) var current: Variante?
    private var leg: Leg?
    private var pending: Request?
    /// When the next Morph may start: the end of the last leg, plus the minimum hold on a Variante.
    private var readyTime = -Double.infinity
    private var returnTime: Double?
    private var state: OrbState = .idle
    private var now: Double = 0

    /// The Variante the Orb ends on once the work already started and queued is done; `nil` is the Blob.
    var destination: Variante? { pending.map(\.variante) ?? leg.map(\.destination) ?? current }

    /// Whether a change of Forma, a Morph or its fade, is under way.
    var isMorphing: Bool { leg != nil }

    /// Whether nothing is under way, waiting or scheduled, not even the return to the Blob: the Orb's Forma stays as it
    /// is until the next request or Stato.
    var isAtRest: Bool { leg == nil && pending == nil && returnTime == nil }

    /// Asks the Orb to take `variante`, or the Blob for `nil`; it replaces any request still waiting and any leg not yet started.
    ///
    /// A Variante cancels the pending return to the Blob.
    mutating func request(_ variante: Variante?, at time: Double) {
        if variante != nil { returnTime = nil }
        if variante == (leg.map(\.destination) ?? current) {
            pending = nil
        } else {
            pending = Request(variante: variante, time: time)
        }
    }

    /// Records that Bubo entered `state`; entering Riposo schedules the return to the Blob, any other Stato cancels it.
    mutating func enter(_ state: OrbState, at time: Double) {
        guard state != self.state else { return }
        self.state = state
        returnTime = state == .idle ? time + Self.returnDelay : nil
    }

    /// Moves the Regia forward to `time`, finishing and starting legs at the exact instants they are due.
    mutating func advance(to time: Double) {
        now = max(now, time)
        while step() {}
    }

    /// What the renderer draws at the time of the latest `advance(to:)`.
    var frame: MorphFrame {
        guard let leg else { return MorphFrame(from: current, to: current, progress: 1, opacity: 1) }
        let linear = Float(min(1, max(0, (now - leg.start) / leg.duration)))
        switch leg.style {
        case .morph:
            return MorphFrame(from: leg.from, to: leg.to, progress: Self.smoothstep(linear), opacity: 1)
        case .fade:
            // No deformation: fades out, switches Forma halfway, fades back in.
            let shown = linear < 0.5 ? leg.from : leg.to
            return MorphFrame(from: shown, to: shown, progress: 1, opacity: abs(1 - 2 * linear))
        }
    }

    /// Takes the next due step, if any; returns whether it took one.
    private mutating func step() -> Bool {
        if let due = returnTime, due <= now {
            returnTime = nil
            request(nil, at: due)
            return true
        }
        if let running = leg {
            guard running.end <= now else { return false }
            current = running.to
            // Back on the Blob, a newer request replaces the leg not yet started.
            if let next = running.next, pending == nil {
                leg = Leg(from: current, to: next, start: running.end, duration: running.duration, style: running.style)
            } else {
                leg = nil
                readyTime = running.end + (current == nil ? 0 : Self.minimumHold)
            }
            return true
        }
        guard let request = pending else { return false }
        let start = max(readyTime, request.time)
        guard start <= now else { return false }
        pending = nil
        guard request.variante != current else { return true }
        leg = makeLeg(to: request.variante, start: start)
        return true
    }

    /// The first leg towards `target`: through the Blob when both ends are Varianti.
    private func makeLeg(to target: Variante?, start: Double) -> Leg {
        if reducesMotion {
            return Leg(from: current, to: target, start: start, duration: Self.fadeDuration, style: .fade)
        }
        if current != nil && target != nil {
            return Leg(from: current, to: nil, start: start, duration: Self.morphDuration / 2, style: .morph,
                       next: target)
        }
        return Leg(from: current, to: target, start: start, duration: Self.morphDuration, style: .morph)
    }

    private static func smoothstep(_ x: Float) -> Float { x * x * (3 - 2 * x) }

    /// A Variante asked for, or the Blob, and when.
    private struct Request {
        var variante: Variante?
        var time: Double
    }

    /// One stretch of a change of Forma, once started always run to the end.
    private struct Leg {
        enum Style { case morph, fade }

        var from: Variante?
        var to: Variante?
        var start: Double
        var duration: Double
        var style: Style
        /// The Variante of the leg that follows from the Blob, when this one only goes back to it.
        var next: Variante?

        var end: Double { start + duration }
        var destination: Variante? { next ?? to }
    }
}

/// What the Regia hands the renderer for one frame; `nil` stands for the Blob.
nonisolated struct MorphFrame: Equatable {
    /// The Variante the leg starts from; equal to `to` when the Orb is still.
    var from: Variante?
    /// The Variante the leg arrives at.
    var to: Variante?
    /// How far the leg is, already eased: 0 is `from`, 1 is `to`.
    var progress: Float
    /// How opaque the Orb is; below 1 only while fading with Reduce Motion on.
    var opacity: Float

    /// The Variante drawn in this frame: of the two ends, the one that is not the Blob.
    var variante: Variante? { to ?? from }

    /// The Forma whose pipeline draws the frame; the renderer draws the Blob for one the shader library lacks.
    var forma: Forma { variante.map { Forma(rawValue: $0.forma) } ?? .blob }

    /// How far the Orb has turned from the Blob into `variante`: 0 is the Blob, 1 is the Variante's Forma.
    var morph: Float {
        guard variante != nil else { return 0 }
        return from == to ? 1 : (to != nil ? progress : 1 - progress)
    }
}
