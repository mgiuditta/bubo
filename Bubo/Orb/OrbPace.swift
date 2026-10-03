/// How often the Orb draws (spec 25, #519): what weighs on the battery is the frame rate, not the Orb's size.
nonisolated enum OrbPace: Equatable {
    /// 60 fps: the Orb listens, thinks, speaks, works or morphs.
    case full
    /// 30 fps: Riposo, or any Stato with Risparmio energia on.
    case half
    /// No frames: Riposo with Riduci movimento and nothing left to move; the Orb draws again when the Stato, the Tinta
    /// or the Variante changes.
    case still

    /// The frames per second of the pace; 0 for ``still``.
    var framesPerSecond: Int {
        switch self {
        case .full: 60
        case .half: 30
        case .still: 0
        }
    }

    /// The pace for one frame of the Orb.
    ///
    /// Risparmio energia keeps the Orb at 30 fps even while it morphs; stopping wins over both.
    ///
    /// - Parameters:
    ///   - state: The Stato the Orb shows.
    ///   - isMorphing: Whether a Morph, or its fade with Riduci movimento, is under way.
    ///   - isSettled: Whether the motion, the Tinta and the Regia del Morph have nothing left to move.
    ///   - isLowPowerModeEnabled: Whether Risparmio energia is on.
    ///   - reducesMotion: Whether Riduci movimento is on.
    init(state: OrbState, isMorphing: Bool, isSettled: Bool, isLowPowerModeEnabled: Bool, reducesMotion: Bool) {
        if state == .idle, reducesMotion, isSettled, !isMorphing {
            self = .still
        } else if isLowPowerModeEnabled {
            self = .half
        } else if isMorphing {
            self = .full
        } else {
            self = state == .idle ? .half : .full
        }
    }
}
