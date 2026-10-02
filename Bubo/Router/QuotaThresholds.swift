import Foundation

/// How much of the 5-hour window the router lets go before it saves the Quota (spec 10): past `stepDown` the automatic
/// choices take one step down the Scala, past `onMac` the Domande go to the Modello locale or Apple Foundation Models.
///
/// Never a block: the user's choices and preferences stay as they are. Set in Impostazioni › Modelli.
nonisolated struct QuotaThresholds: Equatable, Sendable {
    /// The share of the window, from 0 to 1, past which the automatic choices take one step down the Scala.
    var stepDown = 0.8
    /// The share of the window, from 0 to 1, past which the Domande stay on the Mac when they can.
    var onMac = 0.95

    /// The defaults key of `stepDown`.
    static let stepDownKey = "router.quota.stepDown"
    /// The defaults key of `onMac`.
    static let onMacKey = "router.quota.onMac"

    /// The thresholds saved in `defaults`, or the spec's 80% and 95% where none is.
    static func saved(in defaults: UserDefaults) -> Self {
        var thresholds = Self()
        if let stepDown = defaults.object(forKey: stepDownKey) as? Double { thresholds.stepDown = stepDown }
        if let onMac = defaults.object(forKey: onMacKey) as? Double { thresholds.onMac = onMac }
        return thresholds
    }
}
