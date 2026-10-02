import Foundation

/// How many times each command was run from the Palette, for the most used ones with an empty box.
///
/// Only titles and counts, kept in `UserDefaults` on this Mac.
struct CommandUsage {
    /// The `UserDefaults` key of the counts.
    static let defaultsKey = "paletteCommandUses"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Counts one more run of `command`.
    func record(_ command: PaletteCommand) {
        var counts = self.counts
        counts[command.title, default: 0] += 1
        defaults.set(counts, forKey: Self.defaultsKey)
    }

    /// Up to `limit` of `commands` already run, most run first; ties keep the menu order.
    func mostUsed(among commands: [PaletteCommand], limit: Int = 5) -> [PaletteCommand] {
        let counts = self.counts
        let used = commands.enumerated().filter { counts[$0.element.title, default: 0] > 0 }
        return used.sorted { first, second in
            let (firstCount, secondCount) = (counts[first.element.title, default: 0], counts[second.element.title, default: 0])
            return firstCount != secondCount ? firstCount > secondCount : first.offset < second.offset
        }
        .prefix(limit).map(\.element)
    }

    private var counts: [String: Int] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int] ?? [:]
    }
}
