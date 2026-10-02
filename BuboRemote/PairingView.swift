import RemoteKit
import SwiftUI

/// Pairing on the iPhone: the QR viewfinder, then the code, what arrives on the iPhone and Face ID (spec 21).
struct PairingView: View {
    let pairing: RemoteModel.Pairing
    let model: RemoteModel

    var body: some View {
        content
            .navigationTitle("Accoppia un Mac")
            .toolbar {
                if !model.macs.isEmpty {
                    Button("Annulla", role: .cancel) { model.cancelPairing() }
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch pairing {
        case .scanning:
            ScanningView(model: model)
        case .reviewing(let scanned):
            ReviewView(scanned: scanned, model: model)
        case .sent(let macName):
            ContentUnavailableView {
                Label("Conferma sul Mac", systemImage: "checkmark.shield")
            } description: {
                Text("Su «\(macName)» controlla che il codice sia lo stesso e scegli Accoppia.")
            } actions: {
                Button("Fine") { model.finishPairing() }
                    .buttonStyle(.borderedProminent)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Accoppiamento non riuscito", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Inquadra di nuovo") { model.startPairing() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// The camera on the Mac's QR.
private struct ScanningView: View {
    let model: RemoteModel

    var body: some View {
        VStack(spacing: 16) {
            if QRScanner.isAvailable {
                QRScanner { model.scanned($0) }
                    .clipShape(.rect(cornerRadius: 16))
                    .accessibilityLabel("Mirino del QR")
            } else {
                ContentUnavailableView("Fotocamera non disponibile", systemImage: "camera",
                                       description: Text("Per inquadrare il QR, consenti a Bubo di usare la fotocamera in Impostazioni."))
            }
            Text("Sul Mac, in Bubo apri Impostazioni › iPhone, accendi il Telecomando e scegli Mostra il QR.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Serve lo stesso Account Apple su Mac e iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

/// The verification code, what arrives on the iPhone, and "Accoppia con Face ID".
private struct ReviewView: View {
    let scanned: RemoteModel.ScannedInvitation
    let model: RemoteModel
    @State private var isPairing = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text("Codice di verifica")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(code)
                        .font(.system(.largeTitle, design: .monospaced))
                        .accessibilityLabel(scanned.secrets.verificationCode.map(String.init).joined(separator: " "))
                    Text("Deve essere uguale a quello su «\(scanned.invitation.macName)».")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
            Section("Cosa arriva sull'iPhone") {
                Text("Cifrati, con una chiave che hanno solo questo iPhone e il Mac: titolo della Sessione, Progetto, Attività, Fase, estratto degli ultimi messaggi, Richiesta in attesa (strumento, comando, percorso) e statistiche del diff.")
                Text("Mai i contenuti dei file, la trascrizione completa o gli Allegati.")
            }
            Section {
                Button {
                    isPairing = true
                    Task {
                        await model.pair()
                        isPairing = false
                    }
                } label: {
                    Label("Accoppia con Face ID", systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPairing)
            }
        }
    }

    private var code: String {
        let digits = scanned.secrets.verificationCode
        return digits.prefix(3) + " " + digits.dropFirst(3)
    }
}
