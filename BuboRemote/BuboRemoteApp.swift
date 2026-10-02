import SwiftUI

/// The Telecomando: Bubo's iPhone app, which follows the Mac's Sessioni and decides its Richieste (spec 21).
@main
struct BuboRemoteApp: App {
    @State private var model = RemoteModel.live()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .task { await model.run() }
        }
    }
}
