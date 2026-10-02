import Foundation

/// The used part of the Claude subscription limits, as `claude` reports it; never estimated by Bubo.
nonisolated struct Quota: Codable, Equatable, Sendable {
    /// A limit window: how much of it is used and when it starts again from zero.
    struct Window: Codable, Equatable, Sendable {
        /// The share of the window used, from 0 to 1.
        var used: Double
        /// When the window starts again from zero.
        var resetsAt: Date

        private enum CodingKeys: String, CodingKey {
            case used, resetsAt
        }

        /// Creates a window with `used` of it gone until `resetsAt`.
        init(used: Double, resetsAt: Date) {
            self.used = used
            self.resetsAt = resetsAt
        }

        /// Decodes a window from the bridge, where `resetsAt` is in Unix seconds.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            used = try container.decode(Double.self, forKey: .used)
            resetsAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .resetsAt))
        }

        /// Encodes the window as the bridge sends it, `resetsAt` in Unix seconds.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(used, forKey: .used)
            try container.encode(resetsAt.timeIntervalSince1970, forKey: .resetsAt)
        }
    }

    /// The subscription limit that stopped a request, as `claude` reports it.
    struct Limit: Equatable, Sendable {
        /// The window `claude` names, such as `five_hour` or `seven_day_opus`; `nil` when it names none.
        var window: String?
        /// When the window starts again from zero, if `claude` says.
        var resetsAt: Date?

        /// The `claude` model alias to try instead: Opus at Sonnet's own limit, Sonnet otherwise.
        var otherModel: String {
            window == "seven_day_sonnet" ? "opus" : "sonnet"
        }
    }

    /// The 5-hour window, if `claude` reported it.
    var fiveHour: Window?
    /// The weekly window, if `claude` reported it.
    var sevenDay: Window?

    /// The key of the last Quota `claude` reported, kept for the next launch.
    static let defaultsKey = "lastQuota"

    /// The Quota last saved in `defaults` with `save(to:)`; empty when there is none, or it cannot be read.
    ///
    /// Shown until `claude` reports a newer one; its windows whose reset has passed stay hidden.
    static func saved(in defaults: UserDefaults) -> Quota {
        guard let data = defaults.data(forKey: defaultsKey) else { return Quota() }
        return (try? JSONDecoder().decode(Quota.self, from: data)) ?? Quota()
    }

    /// Saves this Quota in `defaults`, for the next launch.
    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// This Quota updated with the windows in `newer`; a window `newer` lacks stays as it was.
    func merging(_ newer: Quota) -> Quota {
        Quota(fiveHour: newer.fiveHour ?? fiveHour, sevenDay: newer.sevenDay ?? sevenDay)
    }
}
