import SwiftUI

/// A plugin's state as a dot, always with a label for VoiceOver: achromatic, with `danger` only for an error.
struct PluginStatusDot: View {
    enum Status {
        case on, off, failed, notInstalled

        /// The status of `entry`, which failed to load when `failed`.
        init(_ entry: PluginEntry, failed: Bool) {
            self = failed ? .failed : entry.isInstalled ? (entry.isEnabled ? .on : .off) : .notInstalled
        }
    }

    let status: Status
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Group {
            switch status {
            case .on:
                Circle().fill(prominence == .increased ? Palette.ink : Palette.textPrimary)
                    .accessibilityLabel(Text("Attivo"))
            case .off:
                Circle().strokeBorder(prominence == .increased ? Palette.ink : Palette.textFaint, lineWidth: 1)
                    .accessibilityLabel(Text("Disattivato"))
            case .failed:
                Circle().fill(Palette.danger)
                    .accessibilityLabel(Text("Errore"))
            case .notInstalled:
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 7, height: 7)
    }
}
