import SwiftUI

/// The Orbita Vista of the HUD: the open Sessioni as satellites on the Orb's ring, Attende te on top and larger,
/// the others alternating on the sides; the Quota as arcs on the ring; the chosen Sessione's card under the Orb.
struct SessionOrbit: View {
    let store: SessionStore
    let quota: Quota
    /// The Sessione whose card is shown; until one is chosen, the one waiting the longest.
    @State private var selection: Session.ID?

    private var sessions: [Session] {
        Session.inActivityOrder(store.sessions.reversed().filter { $0.phase == .aperta })
    }

    private var selected: Session? {
        sessions.first { $0.id == selection } ?? sessions.first { $0.activity == .attende }
    }

    var body: some View {
        let sessions = sessions
        VStack(spacing: Spacing.small) {
            OrbPlaceholder()
                .overlay { QuotaArcs(quota: quota) }
                .overlay {
                    GeometryReader { proxy in
                        let angles = Self.angles(waiting: sessions.count { $0.activity == .attende },
                                                 others: sessions.count { $0.activity != .attende })
                        ForEach(Array(zip(sessions, angles)), id: \.0.id) { session, angle in
                            Satellite(session: session, isSelected: session.id == selected?.id) {
                                selection = session.id
                            }
                            .position(Self.point(at: angle, in: proxy.size))
                        }
                    }
                    .animation(Motion.isReduced ? nil : Motion.emphasized, value: sessions.map(\.activity))
                }
                .frame(maxWidth: 520, maxHeight: 520)
                .padding(Spacing.large)
            if let selected {
                SessionRow(session: selected, store: store)
                    .frame(width: 380, alignment: .leading)
                    .padding(Spacing.xxSmall)
                    .glassEffect(.regular, in: .rect(cornerRadius: CornerRadius.large))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sessioni")
    }

    /// Where the satellites sit on the ring: `waiting` around the top, 26° apart; then `others` alternating right
    /// and left, from just under the horizon upwards, 24° apart on each side.
    static func angles(waiting: Int, others: Int) -> [Angle] {
        let top = (0..<waiting).map { index in
            Angle.degrees(-90 + (Double(index) - Double(waiting - 1) / 2) * 26)
        }
        let sides = (0..<others).map { index in
            let step = Double(index / 2) * 24
            return Angle.degrees(index.isMultiple(of: 2) ? 12 - step : 168 + step)
        }
        return top + sides
    }

    /// The point at `angle` on the ring of an Orb drawn in `size`.
    private static func point(at angle: Angle, in size: CGSize) -> CGPoint {
        let radius = min(size.width, size.height) * 0.47
        return CGPoint(x: size.width / 2 + cos(angle.radians) * radius,
                       y: size.height / 2 + sin(angle.radians) * radius)
    }
}

/// A Sessione on the Orb's ring: a dot in the colour of its Attività, larger for Attende te, and its title.
private struct Satellite: View {
    let session: Session
    let isSelected: Bool
    let select: () -> Void

    private var isWaiting: Bool { session.activity == .attende }

    var body: some View {
        Button(action: select) {
            VStack(spacing: Spacing.xxSmall) {
                Circle()
                    .fill(session.activity.color)
                    .frame(width: isWaiting ? 20 : 14, height: isWaiting ? 20 : 14)
                    .shadow(color: isWaiting ? Palette.attention.opacity(0.8) : .clear, radius: 10)
                    .overlay {
                        Circle()
                            .stroke(Palette.lineStrong, lineWidth: isSelected ? 1.5 : 0)
                            .padding(-4)
                    }
                Text(verbatim: session.title)
                    .font(Typography.mono(size: 10))
                    .foregroundStyle(isWaiting ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 140)
                    .padding(.horizontal, Spacing.xxSmall)
                    .background(Palette.ink.opacity(0.7), in: .rect(cornerRadius: CornerRadius.small))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: session.title))
        .accessibilityValue(Text(session.activity.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The Quota as two arcs on the Orb's ring: the 5-hour window outside, the weekly one inside, fainter.
///
/// Only a picture: the Quota with its resets is read in the `QuotaView` at the top of the HUD.
private struct QuotaArcs: View {
    let quota: Quota

    var body: some View {
        TimelineView(.everyMinute) { context in
            ZStack {
                arc(quota.fiveHour, at: context.date, scale: 0.95, color: Palette.attention)
                arc(quota.sevenDay, at: context.date, scale: 0.93, color: Palette.attention.opacity(0.45))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func arc(_ window: Quota.Window?, at date: Date, scale: CGFloat, color: Color) -> some View {
        if let window, window.resetsAt > date {
            ZStack {
                Circle().stroke(Palette.line, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: min(max(window.used, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .scaleEffect(scale)
        }
    }
}
