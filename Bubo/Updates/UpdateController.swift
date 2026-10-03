import Foundation
import os
import Sparkle

/// Bubo's updater: Sparkle with its standard windows, the Canale and the choices of Impostazioni › Aggiornamenti
/// (spec 27).
///
/// The updater starts only in a build that may update itself (``UpdateEligibility``); elsewhere every control is off.
@Observable
final class UpdateController: NSObject, SPUUpdaterDelegate {
    /// The defaults key of "Ricevi le beta".
    static let receivesBetaKey = "updates.receivesBeta"
    /// The Canale of the betas in the appcast (`sparkle:channel`), the same `appcast.sh` writes.
    static let betaChannel = "beta"

    /// Whether this build updates itself.
    let isEnabled: Bool
    /// Whether "Controlla aggiornamenti…" can run now: false while a check runs and when updates are off.
    private(set) var canCheckForUpdates = false
    /// When the appcast was last read; `nil` if never.
    private(set) var lastCheckDate: Date?
    /// Whether Sparkle checks once a day by itself.
    var checksAutomatically: Bool {
        didSet { updater.automaticallyChecksForUpdates = checksAutomatically }
    }
    /// Whether Sparkle downloads in the background and installs on quit.
    var installsOnQuit: Bool {
        didSet { updater.automaticallyDownloadsUpdates = installsOnQuit }
    }
    /// "Ricevi le beta", off by default. Turning it off never offers an older version: Sparkle only offers newer ones.
    var receivesBeta: Bool {
        didSet {
            defaults.set(receivesBeta, forKey: Self.receivesBetaKey)
            // The next cycle reads the appcast with the new Canale.
            if isStarted { updater.resetUpdateCycleAfterShortDelay() }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updater: SPUUpdater!
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    /// The version the running check found, until its cycle finishes.
    @ObservationIgnored private var foundVersion: String?
    /// The caller of ``checkForUpdateInformation()``, waiting for the cycle to finish.
    @ObservationIgnored private var pendingInformation: CheckedContinuation<UpdateCheckOutcome, Never>?

    /// Creates the updater of `hostBundle`, not started yet.
    ///
    /// - Parameters:
    ///   - hostBundle: The app Sparkle updates, with the `SU*` keys in its Info.plist.
    ///   - defaults: Where "Ricevi le beta" is kept.
    ///   - isEnabled: Whether the build may update itself; ``start()`` does nothing otherwise.
    init(hostBundle: Bundle = .main, defaults: UserDefaults = .standard,
         isEnabled: Bool = UpdateEligibility.current.allowsUpdates) {
        self.defaults = defaults
        self.isEnabled = isEnabled
        receivesBeta = defaults.bool(forKey: Self.receivesBetaKey)
        checksAutomatically = false
        installsOnQuit = false
        super.init()
        let userDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        updater = SPUUpdater(hostBundle: hostBundle, applicationBundle: hostBundle, userDriver: userDriver, delegate: self)
        checksAutomatically = updater.automaticallyChecksForUpdates
        installsOnQuit = updater.automaticallyDownloadsUpdates
        lastCheckDate = updater.lastUpdateCheckDate
    }

    /// Starts the scheduled checks, in a build that may update itself; logs and stays off if Sparkle refuses its
    /// configuration.
    func start() {
        guard isEnabled, !isStarted else { return }
        do {
            try updater.start()
        } catch {
            Logger.updates.error("Sparkle not started: \(error.localizedDescription, privacy: .public)")
            return
        }
        isStarted = true
        Logger.updates.info("Feed \(self.updater.feedURL?.absoluteString ?? "-", privacy: .public)")
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            // Sparkle changes it on the main thread.
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    /// Checks now, with Sparkle's windows: the user asked.
    func checkForUpdates() {
        guard isStarted else { return }
        updater.checkForUpdates()
    }

    /// Checks without any window and returns what the appcast offers this build.
    ///
    /// Starts the updater if needed. A second call while one is waiting returns ``UpdateCheckOutcome/failed(code:)``.
    func checkForUpdateInformation() async -> UpdateCheckOutcome {
        start()
        guard isStarted, pendingInformation == nil else { return .failed(code: Int(SUError.invalidUpdaterError.rawValue)) }
        return await withCheckedContinuation { continuation in
            pendingInformation = continuation
            foundVersion = nil
            updater.checkForUpdateInformation()
        }
    }

    // MARK: SPUUpdaterDelegate

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        receivesBeta ? [Self.betaChannel] : []
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        foundVersion = item.versionString
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastCheckDate = updater.lastUpdateCheckDate
        // No newer version is an error for Sparkle, not for Bubo.
        let failure = (error as NSError?).flatMap { $0.code == Int(SUError.noUpdateError.rawValue) ? nil : $0 }
        if let failure {
            Logger.updates.error("Update check failed: \(failure.localizedDescription, privacy: .public)")
        }
        guard updateCheck == .updateInformation, let pending = pendingInformation else { return }
        pendingInformation = nil
        if let foundVersion {
            pending.resume(returning: .found(version: foundVersion))
        } else if let failure {
            pending.resume(returning: .failed(code: failure.code))
        } else {
            pending.resume(returning: .upToDate)
        }
    }
}

extension Logger {
    /// Sparkle's start and failed checks.
    static let updates = Logger(subsystem: "com.mgiuditta.bubo", category: "updates")
}
