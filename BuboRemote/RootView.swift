import SwiftUI

/// The pairing while there is one in progress, otherwise the Sessioni and Mac tabs.
struct RootView: View {
    let model: RemoteModel

    var body: some View {
        if let pairing = model.pairing {
            NavigationStack {
                PairingView(pairing: pairing, model: model)
            }
        } else {
            TabView {
                Tab("Sessioni", systemImage: "rectangle.stack") {
                    NavigationStack {
                        SessionsView(model: model)
                    }
                }
                Tab("Mac", systemImage: "laptopcomputer") {
                    NavigationStack {
                        MacsView(model: model)
                    }
                }
            }
            .task { await model.keepRefreshing() }
        }
    }
}
