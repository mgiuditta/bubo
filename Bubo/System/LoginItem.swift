import ServiceManagement

/// Starts Bubo at login through `SMAppService`.
enum LoginItem {
    /// Whether Bubo is registered to open at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Whether the registration waits for the user's approval in System Settings, which can also revoke it.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Opens the Login Items of System Settings, where the user approves Bubo.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Registers or unregisters Bubo as a login item.
    ///
    /// - Throws: The `SMAppService` error, for example when the app is not in a
    ///   location the system accepts.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
