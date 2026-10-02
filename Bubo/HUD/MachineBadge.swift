import SwiftUI

/// The label of a Macchina: `utente@hostname` with its status dot.
///
/// The dot never relies on color alone: filled when Connessa, a ring when Irraggiungibile, a cross when Bloccata;
/// only the last two are in `danger` (design system, ADR 0004). VoiceOver reads the state with the name.
struct MachineBadge: View {
    let machine: Machine
    let status: MachineStatus?

    var body: some View {
        HStack(spacing: Spacing.xxSmall) {
            if let status {
                Image(systemName: Self.symbol(for: status))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(status == .connected ? Palette.textSecondary : Palette.danger)
                    .accessibilityHidden(true)
            }
            Text(verbatim: machine.address)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// The shape of the dot, distinct for each state.
    static func symbol(for status: MachineStatus) -> String {
        switch status {
        case .connected: "circle.fill"
        case .unreachable: "circle"
        case .blocked: "xmark.circle.fill"
        }
    }

    private var accessibilityText: Text {
        guard let status else { return Text(verbatim: machine.address) }
        return Text("\(machine.address), \(Text(status.title))")
    }
}

extension MachineStatus {
    /// The state's name, read by VoiceOver.
    var title: LocalizedStringResource {
        switch self {
        case .connected: "Connessa"
        case .unreachable: "Irraggiungibile"
        case .blocked: "Bloccata"
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        let machine = Machine(alias: "nas", user: "ada", hostname: "nas.lan")
        MachineBadge(machine: machine, status: .connected)
        MachineBadge(machine: machine, status: .unreachable)
        MachineBadge(machine: machine, status: .blocked)
        MachineBadge(machine: machine, status: nil)
    }
    .padding()
}
