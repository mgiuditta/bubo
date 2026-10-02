/// What the Plugin window's sidebar can select.
enum PluginSidebarItem: Hashable {
    case installed, toFix, updates, marketplace(String), mcpServers

    /// Da sistemare when it has something, a plugin's problem or an MCP server waiting for a login, otherwise
    /// Installati.
    static func initialSelection(in snapshot: PluginSnapshot, serversNeedingAuthentication: Int = 0) -> PluginSidebarItem {
        snapshot.problems.isEmpty && serversNeedingAuthentication == 0 ? .installed : .toFix
    }
}
