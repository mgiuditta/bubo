import SwiftUI

/// The Striscia Vista of the HUD: the open Sessioni as cards in a row above the prompt, Attende te first and wider.
struct SessionStrip: View {
    let store: SessionStore

    private var sessions: [Session] {
        Session.inActivityOrder(store.sessions.reversed().filter { $0.phase == .aperta })
    }

    var body: some View {
        let sessions = sessions
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: Spacing.xSmall) {
                HStack(alignment: .top, spacing: Spacing.xSmall) {
                    ForEach(sessions) { session in
                        let isWaiting = session.activity == .attende
                        SessionRow(session: session, store: store)
                            .frame(width: isWaiting ? 320 : 200, alignment: .leading)
                            .padding(Spacing.xxSmall)
                            .glassEffect(isWaiting ? .regular.tint(Palette.attention.opacity(0.12)) : .regular,
                                         in: .rect(cornerRadius: CornerRadius.large))
                    }
                }
                .padding(Spacing.xxSmall)
            }
        }
        .scrollIndicators(.never)
        .animation(Motion.isReduced ? nil : Motion.emphasized, value: sessions.map(\.activity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sessioni")
    }
}
