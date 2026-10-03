import SwiftUI

/// The Modalità autonoma of a Sessione in its own worktree, from the next turn; turning it on with the Sandbox off
/// proposes the Sandbox too, with one switch (spec 22).
struct AutonomyToggle: View {
    let isAutonomous: Bool
    /// Whether the Progetto has the Sandbox on.
    let isSandboxed: Bool
    /// Whether the Sandbox may be proposed: false in a build without it.
    var offersSandbox = true
    let setAutonomous: (Bool) -> Void
    let setSandboxed: (Bool) -> Void
    @State private var isOn = false
    @State private var isSandboxOn = false
    /// Whether the Sandbox is proposed: from when the Modalità autonoma is turned on with the Sandbox off, until it is
    /// turned off.
    @State private var proposesSandbox = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Toggle("Modalità autonoma", isOn: $isOn)
                .help("Claude lavora senza chiederti il permesso fino al livello 3, solo nella copia del Progetto. I livelli 4 e 5 chiedono comunque. Vale dal prossimo turno.")
            if proposesSandbox {
                Toggle("Accendi anche la Sandbox", isOn: $isSandboxOn)
                    .help("Consigliata con la Modalità autonoma: i comandi e le modifiche di Claude restano nella copia del Progetto. Vale per tutto il Progetto, dal prossimo turno.")
            }
        }
        .toggleStyle(.switch)
        .tint(Palette.switchTrack)
        .controlSize(.mini)
        .font(Typography.mono(size: 11))
        .foregroundStyle(Palette.textSecondary)
        .onAppear {
            isOn = isAutonomous
            isSandboxOn = isSandboxed
        }
        .onChange(of: isAutonomous) { _, isAutonomous in isOn = isAutonomous }
        .onChange(of: isSandboxed) { _, isSandboxed in isSandboxOn = isSandboxed }
        .onChange(of: isOn) { _, isOn in
            guard isOn != isAutonomous else { return }
            if isOn && !isSandboxed && offersSandbox { proposesSandbox = true }
            if !isOn { proposesSandbox = false }
            setAutonomous(isOn)
        }
        .onChange(of: isSandboxOn) { _, isSandboxOn in
            guard isSandboxOn != isSandboxed else { return }
            setSandboxed(isSandboxOn)
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        AutonomyToggle(isAutonomous: false, isSandboxed: false) { _ in } setSandboxed: { _ in }
        AutonomyToggle(isAutonomous: true, isSandboxed: true) { _ in } setSandboxed: { _ in }
    }
    .padding()
    .background(Palette.ink)
}
