import SwiftUI

/// The Sandbox of a Sessione, on or off, always shown while it is open (spec 22); it opens the Progetto's settings.
struct SandboxIndicator: View {
    let state: SandboxState
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Label {
                Text(state.title)
            } icon: {
                Image(systemName: state.isSandboxedNow ? "lock.shield" : "lock.open")
            }
            .font(Typography.mono(size: 11))
            .foregroundStyle(state.isSandboxedNow ? Palette.textPrimary : Palette.textSecondary)
        }
        .buttonStyle(.borderless)
        .help(state.isSandboxedNow
            ? Text("I comandi di Claude scrivono solo nella cartella della Sessione, nelle cartelle temporanee e nelle cache dei pacchetti, e raggiungono solo i registri dei pacchetti. Il terminale e i server non sono in Sandbox.")
            : Text("I comandi di Claude girano con i tuoi permessi. Accendi la Sandbox nella configurazione del Progetto."))
    }
}

#Preview {
    VStack(alignment: .leading) {
        SandboxIndicator(state: .on) {}
        SandboxIndicator(state: .off) {}
        SandboxIndicator(state: .offFromNextTurn) {}
    }
    .padding()
    .background(Palette.ink)
}
