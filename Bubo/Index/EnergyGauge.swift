import Foundation
import IOKit.ps

/// Why the Indice stops computing vectors for now.
nonisolated enum IndexPause: Equatable, Sendable {
    /// Low Power Mode is on.
    case lowPowerMode
    /// The Mac runs on a battery below ``EnergyState/minimumBatteryLevel``.
    case lowBattery
}

/// What the Mac's energy allows.
nonisolated struct EnergyState: Equatable, Sendable {
    /// The battery level under which a Mac on battery pauses the vectors: 20% (spec).
    static let minimumBatteryLevel = 0.2

    /// Whether Low Power Mode is on.
    var isLowPowerModeEnabled = false
    /// From 0 to 1 while the Mac runs on its battery; `nil` on the power adapter or without a battery.
    var batteryLevel: Double?

    /// Why the vectors must wait; `nil` when they can go on.
    var pause: IndexPause? {
        if isLowPowerModeEnabled { return .lowPowerMode }
        if let batteryLevel, batteryLevel < Self.minimumBatteryLevel { return .lowBattery }
        return nil
    }
}

/// Reads the Mac's energy and waits for it to change.
nonisolated protocol EnergyGauge: Sendable {
    /// The energy now.
    var current: EnergyState { get }
    /// Returns at the next change of Low Power Mode, after `limit` at the latest, or when cancelled.
    func change(within limit: Duration) async
}

/// The real Mac: `ProcessInfo` for Low Power Mode, `IOPSCopyPowerSourcesInfo` for the battery.
///
/// The battery is read again when asked, never followed: a paused Indice asks once a minute.
nonisolated struct SystemEnergyGauge: EnergyGauge {
    var current: EnergyState {
        EnergyState(isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled, batteryLevel: Self.batteryLevel())
    }

    func change(within limit: Duration) async {
        await withTaskGroup { group in
            group.addTask {
                for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                    return
                }
            }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
    }

    /// The level of the internal battery while it powers the Mac; `nil` on the power adapter or without one.
    private static func batteryLevel() -> Double? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                  let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return Double(capacity) / Double(maximum)
        }
        return nil
    }
}
