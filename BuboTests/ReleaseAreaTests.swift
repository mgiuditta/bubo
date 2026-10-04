import Testing
@testable import Bubo

struct ReleaseAreaTests {
    @Test("An unreleased area is off in a Release build", arguments: ReleaseArea.allCases.filter { !ReleaseArea.released.contains($0) })
    func unreleasedAreaIsOffInRelease(area: ReleaseArea) {
        #expect(!area.isAvailable(isDebugBuild: false, hidesUnreleased: false))
        #expect(!area.isAvailable(isDebugBuild: false, hidesUnreleased: true))
    }

    @Test("The areas left for 1.1 are off in a Release build of 1.0",
          arguments: [ReleaseArea.machines, .remote, .deliveries, .sandbox, .neurons])
    func areasOfOnePointOneAreOffInRelease(area: ReleaseArea) {
        #expect(!ReleaseArea.released.contains(area))
        #expect(!area.isAvailable(isDebugBuild: false, hidesUnreleased: false))
    }

    @Test("A Debug build has every area on", arguments: ReleaseArea.allCases)
    func debugBuildHasEveryAreaOn(area: ReleaseArea) {
        #expect(area.isAvailable(isDebugBuild: true, hidesUnreleased: false))
    }

    @Test("The Debug switch turns the unreleased areas off", arguments: ReleaseArea.allCases.filter { !ReleaseArea.released.contains($0) })
    func debugSwitchTurnsUnreleasedAreasOff(area: ReleaseArea) {
        #expect(!area.isAvailable(isDebugBuild: true, hidesUnreleased: true))
    }

    @Test("Every area names the 1.1 issue it waits for", arguments: ReleaseArea.allCases)
    func everyAreaNamesItsIssue(area: ReleaseArea) {
        #expect(area.issue > 0)
    }
}
