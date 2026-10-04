import Foundation
import Testing
@testable import Bubo

/// The chip that says who the composer writes to.
struct RecipientTests {
    @Test func theBrainIsCalledCervello() {
        #expect(Recipient.brain.name == String(localized: "Cervello"))
        #expect(Recipient.brain.accessibilityLabel == String(localized: "Destinatario: \(String(localized: "Cervello"))"))
    }

    @Test func aProjectIsCalledAsItsFolder() {
        let project = Recipient.project(URL(filePath: "/Users/io/dev/bubo", directoryHint: .isDirectory))
        #expect(project.name == "bubo")
        #expect(project.accessibilityLabel == String(localized: "Destinatario: \("bubo")"))
    }
}
