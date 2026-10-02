import SwiftUI

/// The pairing while there is one in progress, otherwise the Mac tab.
struct RootView: View {
    let model: RemoteModel

    var body: some View {
        NavigationStack {
            if let pairing = model.pairing {
                PairingView(pairing: pairing, model: model)
            } else {
                MacsView(model: model)
            }
        }
    }
}
