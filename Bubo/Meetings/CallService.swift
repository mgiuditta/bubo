import AppKit

/// A service the user's calls run in, as the guided setup of the Secondo cervello asks: its apps come first when a
/// Riunione starts.
nonisolated enum CallService: String, CaseIterable, Identifiable, Sendable {
    case zoom
    case meet
    case teams
    case faceTime
    case slack
    case webex

    var id: Self { self }

    /// The service's own name, the same in every language.
    var name: String {
        switch self {
        case .zoom: "Zoom"
        case .meet: "Google Meet"
        case .teams: "Microsoft Teams"
        case .faceTime: "FaceTime"
        case .slack: "Slack"
        case .webex: "Webex"
        }
    }

    /// The apps the service's calls run in: Google Meet runs in the browser.
    var bundleIDs: [String] {
        switch self {
        case .zoom: ["us.zoom.xos"]
        case .meet: ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.microsoft.edgemac",
                     "org.mozilla.firefox"]
        case .teams: ["com.microsoft.teams2"]
        case .faceTime: ["com.apple.FaceTime"]
        case .slack: ["com.tinyspeck.slackmacgap"]
        case .webex: ["com.cisco.webexmeetingsapp"]
        }
    }

    /// The key of the choice in the user defaults.
    static let defaultsKey = "meetings.callServices"

    /// The services saved in `defaults`, in their order here; none when no choice was made.
    static func saved(in defaults: UserDefaults = .standard) -> [CallService] {
        let names = defaults.stringArray(forKey: defaultsKey) ?? []
        return allCases.filter { names.contains($0.rawValue) }
    }

    /// Saves `services` in `defaults`.
    static func save(_ services: Set<CallService>, in defaults: UserDefaults = .standard) {
        defaults.set(allCases.filter(services.contains).map(\.rawValue), forKey: defaultsKey)
    }

    /// The services with an app on this Mac: the ones the guided setup offers already chosen.
    @MainActor static func installed() -> Set<CallService> {
        Set(allCases.filter { service in
            service.bundleIDs.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        })
    }

    /// The app among `apps` to record first: one of the `services` chosen, else any call app, else none.
    static func preferredApp(among apps: [MeetingApp], services: [CallService]) -> MeetingApp? {
        let chosen = services.flatMap(\.bundleIDs)
        return apps.first { chosen.contains($0.bundleID) } ?? apps.first { MeetingApp.callApps.contains($0.bundleID) }
    }
}
