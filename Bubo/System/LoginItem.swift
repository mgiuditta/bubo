import ServiceManagement

/// Starts Bubo at login through `SMAppService`.
enum LoginItem {
    /// Whether Bubo is registered to open at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
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
