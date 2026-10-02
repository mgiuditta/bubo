/// A group of the Plugin window's list: one Marketplace's results while searching, otherwise the whole list.
struct PluginSection: Identifiable, Equatable {
    /// The Marketplace of the results; `nil` for the list of a sidebar item.
    let marketplace: String?
    let entries: [PluginEntry]

    var id: String { marketplace ?? "" }
}
