import CoreImage.CIFilterBuiltins
import RemoteKit
import SwiftUI

/// Impostazioni › iPhone: the Telecomando switch with the consent, the pairing QR and the paired iPhones (spec 21).
struct RemoteSettingsView: View {
    @Environment(PairingController.self) private var remote
    @AppStorage(PairingController.isOnKey) private var isOn = false

    var body: some View {
        Form {
            Section {
                Toggle("Telecomando", isOn: $isOn)
                    .tint(Palette.switchTrack)
                Text("Con l'app Bubo per iPhone segui le Sessioni e decidi le Richieste da lontano. Escono dal Mac, cifrati con una chiave che hanno solo questo Mac e i tuoi iPhone: titolo della Sessione, Progetto, Attività, Fase, estratto degli ultimi messaggi, Richiesta in attesa (strumento, comando, percorso) e statistiche del diff. Mai i contenuti dei file, la trascrizione completa o gli Allegati. Serve lo stesso Account Apple su Mac e iPhone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if isOn {
                Section("Accoppia un iPhone") {
                    PairingSection(remote: remote)
                }
            }
            if isOn || !remote.devices.isEmpty {
                Section("iPhone accoppiati") {
                    PairedDevicesSection(remote: remote)
                }
            }
        }
        .formStyle(.grouped)
        .task { await remote.run() }
        .onChange(of: isOn) {
            if !isOn { remote.cancel() }
        }
    }
}

/// The pairing in progress: a button, the QR with its countdown, or the code to compare.
private struct PairingSection: View {
    let remote: PairingController

    var body: some View {
        switch remote.phase {
        case .idle:
            Button("Mostra il QR") { remote.startPairing() }
        case .waiting(let invitation):
            WaitingForPhone(invitation: invitation, remote: remote)
        case .expired:
            Text("Il QR è scaduto.")
                .foregroundStyle(.secondary)
            Button("Nuovo QR") { remote.startPairing() }
        case .confirming(let pending):
            VerificationCode(pending: pending, remote: remote)
        }
    }
}

/// The QR on screen, valid 5 minutes, while the controller waits for the iPhone.
private struct WaitingForPhone: View {
    let invitation: PairingInvitation
    let remote: PairingController

    var body: some View {
        VStack(spacing: Spacing.small) {
            QRCode(payload: invitation.qrPayload)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, invitation.expiresAt.timeIntervalSince(context.date))
                Text("Inquadra il QR con l'app Bubo sull'iPhone. Scade tra \(Duration.seconds(remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond))).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Annulla") { remote.cancel() }
        }
        .frame(maxWidth: .infinity)
        .task(id: invitation.id) { await remote.waitForResponse() }
        .task(id: invitation.id) {
            try? await Task.sleep(for: .seconds(invitation.expiresAt.timeIntervalSinceNow))
            if !Task.isCancelled { remote.expire(invitation) }
        }
    }
}

/// The 6-digit code of the iPhone that answered, to compare before confirming.
private struct VerificationCode: View {
    let pending: PairingController.PendingDevice
    let remote: PairingController

    var body: some View {
        VStack(spacing: Spacing.small) {
            Text("«\(pending.name)» mostra lo stesso codice?")
            Text(pending.verificationCode.prefix(3) + " " + pending.verificationCode.dropFirst(3))
                .font(.system(.largeTitle, design: .monospaced))
                .accessibilityLabel(pending.verificationCode.map(String.init).joined(separator: " "))
            Text("Se i codici sono diversi, qualcun altro ha inquadrato il QR: non accoppiare.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Sono diversi", role: .cancel) { remote.cancel() }
                Button("Accoppia") { Task { await remote.confirm() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The paired iPhones, each with Revoca.
private struct PairedDevicesSection: View {
    let remote: PairingController

    var body: some View {
        if remote.devices.isEmpty {
            Text("Nessun iPhone accoppiato.")
                .foregroundStyle(.secondary)
        }
        ForEach(remote.devices) { device in
            PairedDeviceRow(device: device, remote: remote)
        }
        if let failure = remote.failure {
            Text(failure)
                .font(.callout)
                .foregroundStyle(Palette.danger)
        }
    }
}

/// One paired iPhone, with Revoca behind a confirmation.
private struct PairedDeviceRow: View {
    let device: PairedDevice
    let remote: PairingController
    @State private var isConfirming = false

    var body: some View {
        LabeledContent {
            Button("Revoca", role: .destructive) { isConfirming = true }
                .confirmationDialog("Revocare «\(device.name)»?", isPresented: $isConfirming) {
                    Button("Revoca", role: .destructive) { Task { await remote.revoke(device) } }
                } message: {
                    Text("L'iPhone non vedrà più le Sessioni di questo Mac e non potrà decidere le Richieste. La chiave condivisa viene cancellata e i dati in iCloud vengono eliminati.")
                }
        } label: {
            Text(device.name)
            Text("Accoppiato il \(device.pairedAt.formatted(date: .abbreviated, time: .omitted))")
        }
    }
}

/// A QR code, black on light, sharp at any size.
private struct QRCode: View {
    let payload: String

    var body: some View {
        if let image = Self.image(for: payload) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: 200, height: 200)
                .padding(Spacing.small)
                .background(Palette.markLight, in: .rect(cornerRadius: CornerRadius.small))
                .accessibilityLabel("QR per accoppiare l'iPhone")
        }
    }

    private static func image(for payload: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
