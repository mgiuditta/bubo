import SwiftUI

/// The Telecomando: Bubo's iPhone app, which follows the Mac's Sessioni and decides its Richieste (spec 21).
@main
struct BuboRemoteApp: App {
    @State private var model: RemoteModel
    private let notifications: RemoteNotifications

    init() {
        let model = RemoteModel.live()
        _model = State(initialValue: model)
        // The delegate is set at launch, so an action that launches the app reaches it.
        notifications = RemoteNotifications(model: model)
        notifications.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .task { await model.run() }
                .task(id: model.macs.isEmpty) {
                    if !model.macs.isEmpty { await notifications.requestAuthorization() }
                }
        }
    }
}
