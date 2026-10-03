import SwiftUI

/// "Controlla aggiornamenti…", the same in the app menu and in the menu bar; the Palette takes it from the app menu.
struct CheckForUpdatesButton: View {
    @Environment(UpdateController.self) private var updates

    var body: some View {
        Button("Controlla aggiornamenti…", action: updates.checkForUpdates)
            .disabled(!updates.canCheckForUpdates)
    }
}
