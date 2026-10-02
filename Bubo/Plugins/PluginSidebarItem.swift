/// What the Plugin window's sidebar can select.
enum PluginSidebarItem: Hashable {
    case installed, toFix, updates, marketplace(String), mcpServers

    /// Da sistemare when it has something, otherwise Installati.
    static func initialSelection(in snapshot: PluginSnapshot) -> PluginSidebarItem {
        snapshot.problems.isEmpty ? .installed : .toFix
    }
}
