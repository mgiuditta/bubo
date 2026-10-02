import AppKit
import CoreGraphics

/// Whether the user is at the Mac: input in the last 2 minutes, with the screens awake and the user session in
/// front (spec 21). Then a Richiesta reaches the iPhone without a notification: the Mac already shows it.
///
/// Uses only public signals: the time since the last input event, and the screens and the user session going to
/// sleep or to the background. A Mac locked with the screens on counts as away once its 2 minutes pass.
final class PresenceMonitor {
    /// Input more recent than this means the user is at the Mac.
    static let idleLimit: TimeInterval = 120

    private let idleTime: () -> TimeInterval
    private var isScreenAway = false

    /// Creates a monitor that reads the seconds since the last input with `idleTime`.
    init(idleTime: @escaping () -> TimeInterval = PresenceMonitor.systemIdleTime) {
        self.idleTime = idleTime
    }

    /// Whether the user is at the Mac now.
    var isUserAtMac: Bool {
        !isScreenAway && idleTime() < Self.idleLimit
    }

    /// Follows the screens and the user session, until cancelled.
    func run() async {
        async let screensSleep: Void = follow(NSWorkspace.screensDidSleepNotification, isAway: true)
        async let screensWake: Void = follow(NSWorkspace.screensDidWakeNotification, isAway: false)
        async let sessionLeaves: Void = follow(NSWorkspace.sessionDidResignActiveNotification, isAway: true)
        async let sessionReturns: Void = follow(NSWorkspace.sessionDidBecomeActiveNotification, isAway: false)
        _ = await (screensSleep, screensWake, sessionLeaves, sessionReturns)
    }

    private func follow(_ name: NSNotification.Name, isAway: Bool) async {
        for await _ in NSWorkspace.shared.notificationCenter.notifications(named: name) {
            isScreenAway = isAway
        }
    }

    /// Seconds since the last keyboard, mouse or trackpad event in the user session.
    nonisolated static func systemIdleTime() -> TimeInterval {
        // kCGAnyInputEventType (~0): every kind of input.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
