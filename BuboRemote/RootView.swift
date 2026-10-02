import SwiftUI

/// The pairing while there is one in progress, otherwise the tabs; the app opens on Attende te (spec 21).
struct RootView: View {
    let model: RemoteModel
    @State private var tab = RootTab.waiting

    var body: some View {
        if let pairing = model.pairing {
            NavigationStack {
                PairingView(pairing: pairing, model: model)
            }
        } else {
            TabView(selection: $tab) {
                Tab("Attende te", systemImage: "hand.raised", value: .waiting) {
                    NavigationStack {
                        WaitingView(model: model)
                    }
                }
                .badge(model.waitingRequests.count)
                Tab("Sessioni", systemImage: "rectangle.stack", value: .sessions) {
                    NavigationStack {
                        SessionsView(model: model)
                    }
                }
                Tab("Mac", systemImage: "laptopcomputer", value: .macs) {
                    NavigationStack {
                        MacsView(model: model)
                    }
                }
            }
            .task { await model.keepRefreshing() }
            .onChange(of: model.focusedRequest) { _, request in
                if request != nil { tab = .waiting }
            }
        }
    }
}

/// The tabs of the app.
enum RootTab: Hashable {
    case waiting, sessions, macs
}
