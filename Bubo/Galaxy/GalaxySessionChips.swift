import SwiftUI

/// The chips of the Progetto's Sessioni at the top of the Galassia's list: one shows the files of its Sessione and
/// makes the camera follow its comet; a drag on the map lets the comet go.
struct GalaxySessionChips: View {
    let model: GalaxyModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xxSmall) {
                chip(Text("Tutte le Sessioni"), isSelected: model.filter == nil) { model.showAllSessions() }
                ForEach(model.sessions) { session in
                    chip(Text(verbatim: "\(session.sign) \(session.title)"), isSelected: model.filter == session.id) {
                        model.toggleFilter(session.id)
                    }
                    // The sign is for the eye: VoiceOver says the title and the Attività.
                    .accessibilityLabel(Text(verbatim: session.title))
                    .accessibilityValue(Text(session.activity.title))
                    .help("Mostra i file di questa Sessione e segue la sua cometa")
                }
            }
        }
        .scrollIndicators(.hidden)
        .controlSize(.small)
    }

    private func chip(_ title: Text, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .lineLimit(1)
                .frame(maxWidth: 160)
        }
        .buttonStyle(.bordered)
        // The container stays achromatic (ADR 0004).
        .tint(isSelected ? Palette.textPrimary : nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
