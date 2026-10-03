import AppKit

/// An open app whose audio a Riunione can record: the call's app, chosen by the user.
nonisolated struct MeetingApp: Identifiable, Hashable, Sendable {
    var name: String
    var bundleID: String

    var id: String { bundleID }

    /// The apps calls usually run in, first in the list when open.
    static let callApps = [
        "us.zoom.xos", "com.microsoft.teams2", "com.google.Chrome", "com.apple.Safari", "com.apple.FaceTime",
        "com.tinyspeck.slackmacgap", "com.cisco.webexmeetingsapp", "com.hnc.Discord", "company.thebrowser.Browser",
        "com.microsoft.edgemac", "org.mozilla.firefox",
    ]

    /// The open apps with a window, the call apps first, then by name.
    @MainActor static func running() -> [MeetingApp] {
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> MeetingApp? in
            guard app.activationPolicy == .regular, let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier else { return nil }
            return MeetingApp(name: app.localizedName ?? bundleID, bundleID: bundleID)
        }
        return ordered(apps)
    }

    /// `apps` with the call apps first, in ``callApps`` order, then the others by name.
    static func ordered(_ apps: [MeetingApp]) -> [MeetingApp] {
        apps.sorted { lhs, rhs in
            let left = callApps.firstIndex(of: lhs.bundleID) ?? callApps.count
            let right = callApps.firstIndex(of: rhs.bundleID) ?? callApps.count
            return left != right ? left < right : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
