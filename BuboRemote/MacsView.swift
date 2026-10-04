import SwiftUI

/// The Mac tab: paired Macs with the Battito, "+ Accoppia un altro Mac", "Revoca questo iPhone" (spec 21).
struct MacsView: View {
    let model: RemoteModel
    @State private var isConfirmingRevoke = false

    var body: some View {
        List {
            Section {
                ForEach(model.macs) { mac in
                    HeartbeatRow(macName: mac.name, heartbeat: model.snapshots[mac.id]?.heartbeat)
                }
                Button("Accoppia un altro Mac", systemImage: "plus") { model.startPairing() }
            } footer: {
                Text("Serve lo stesso Account Apple su Mac e iPhone.")
            }
            Section {
                Button("Revoca questo iPhone", role: .destructive) { isConfirmingRevoke = true }
                    .confirmationDialog("Revocare questo iPhone?", isPresented: $isConfirmingRevoke, titleVisibility: .visible) {
                        Button("Revoca", role: .destructive) { Task { await model.revokeThisPhone() } }
                    } message: {
                        Text("I Mac accoppiati cancellano la chiave e i dati in iCloud. Per usare di nuovo il Telecomando dovrai accoppiare da capo.")
                    }
            }
        }
        .navigationTitle("Mac")
    }
}
