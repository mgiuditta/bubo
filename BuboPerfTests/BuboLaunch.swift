import XCTest

extension XCUIApplication {
    /// Bubo launched as on a fresh start: the windows a previous test closed are not restored.
    ///
    /// - Parameter arguments: Launch arguments added after the ones that turn off window restoration.
    static func bubo(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"] + arguments
        return app
    }
}
