import Foundation
import IOKit.pwr_mgt
import os

/// "Tieni sveglio il Mac": while an Automazione is due within ``window``, an IOKit assertion keeps the Mac from
/// sleeping when idle (spec 19). Off by default; closing the lid puts the Mac to sleep anyway.
final class KeepAwake {
    /// The key of the switch in the user defaults.
    static let defaultsKey = "automations.keepsMacAwake"
    /// How soon an Automazione must be due for the Mac to stay awake.
    static let window: TimeInterval = 2 * 60 * 60

    /// Whether the assertion is held now.
    var isHeld: Bool { assertion != nil }

    private var assertion: IOPMAssertionID?

    isolated deinit {
        release()
    }

    /// Takes the assertion when `isNeeded`, releases it otherwise; nothing when it already is as asked.
    func hold(_ isNeeded: Bool) {
        guard isNeeded != isHeld else { return }
        guard isNeeded else {
            release()
            return
        }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Bubo: un'Automazione nelle prossime 2 ore" as CFString, &id)
        guard result == kIOReturnSuccess else {
            Logger.automations.error("Keep-awake assertion not taken: \(result)")
            return
        }
        assertion = id
        Logger.automations.notice("Keep-awake assertion taken")
    }

    /// Releases the assertion, if held.
    func release() {
        guard let assertion else { return }
        IOPMAssertionRelease(assertion)
        self.assertion = nil
        Logger.automations.notice("Keep-awake assertion released")
    }
}
