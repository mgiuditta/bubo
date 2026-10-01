import Foundation

/// The used part of the Claude subscription limits, as `claude` reports it; never estimated by Bubo.
nonisolated struct Quota: Equatable, Sendable {
    /// A limit window: how much of it is used and when it starts again from zero.
    struct Window: Equatable, Decodable, Sendable {
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
    }

    /// The 5-hour window, if `claude` reported it.
    var fiveHour: Window?
    /// The weekly window, if `claude` reported it.
    var sevenDay: Window?

    /// This Quota updated with the windows in `newer`; a window `newer` lacks stays as it was.
    func merging(_ newer: Quota) -> Quota {
        Quota(fiveHour: newer.fiveHour ?? fiveHour, sevenDay: newer.sevenDay ?? sevenDay)
    }
}
