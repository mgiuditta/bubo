import Foundation
import Observation
import os

/// The Secondo cervello: the folder the user chose, followed by the Indice while Bubo runs.
///
/// Its notes reach the model only through the `cerca` tool, when the model calls it: nothing is added to a
/// conversation on its own.
@Observable
final class SecondBrain {
    /// Creates the Secondo cervello saved in `defaults`, followed by `index` once started.
    init(index: SearchIndex?, defaults: UserDefaults = .standard) {
        self.index = index
        self.defaults = defaults
        location = SecondBrainLocation.saved(in: defaults)
    }

    /// The chosen folder; `nil` while the user has not chosen one.
    private(set) var location: SecondBrainLocation?

    @ObservationIgnored private let index: SearchIndex?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var following: Task<Void, Never>?

    /// Starts following the chosen folder, at its new path when it was moved while Bubo was closed.
    func start() {
        if let location {
            let resolved = location.resolved()
            if resolved != location { remember(resolved) }
        }
        follow()
    }

    /// Makes `folder` the Secondo cervello, replacing the previous one in the Indice.
    func choose(_ folder: URL) {
        remember(SecondBrainLocation(folder: folder))
        follow()
    }

    /// Stops using the Secondo cervello: the Indice forgets its notes; the folder is left as it is.
    func stopUsing() {
        remember(nil)
        follow()
    }

    private func remember(_ location: SecondBrainLocation?) {
        self.location = location
        SecondBrainLocation.save(location, in: defaults)
        Logger.index.notice("Secondo cervello \(location == nil ? "removed" : "chosen", privacy: .public)")
    }

    private func follow() {
        following?.cancel()
        let folder = location?.url
        following = Task(priority: .utility) { [index] in
            await index?.keepSecondBrainFresh(at: folder)
        }
    }
}
