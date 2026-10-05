import SwiftUI

/// Colore di Bubo and Riduci movimento.
struct AppearanceSettingsView: View {
    @AppStorage(Motion.reducesMotionKey) private var reducesMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
    @AppStorage(OrbColor.defaultsKey) private var orbColor = OrbColor.automatic

    var body: some View {
        Form {
            Section {
                LabeledContent("Colore di Bubo") {
                    HStack(spacing: Spacing.xs) {
                        ForEach(OrbColor.allCases) { color in
                            swatch(color)
                        }
                    }
                }
                Group {
                    if orbColor == .automatic {
                        Text("Bubo prende il colore del fornitore che risponde.")
                    } else {
                        Text("Bubo resta di questo colore con ogni fornitore.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            // The system's setting wins: the switch shows it on and cannot turn it off.
            Toggle("Riduci movimento", isOn: systemReducesMotion ? .constant(true) : $reducesMotion)
                .tint(Palette.switchTrack)
                .disabled(systemReducesMotion)
            Group {
                if systemReducesMotion {
                    Text("Attivo nelle Impostazioni di Sistema, in Accessibilità › Display.")
                } else {
                    Text("L'Orb sfuma invece di cambiare forma e si muove più piano.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    /// A round button that gives the Orb `color`; automatic is drawn as the providers' colours in a ring.
    private func swatch(_ color: OrbColor) -> some View {
        Button {
            orbColor = color
        } label: {
            Group {
                if color == .automatic {
                    Circle().fill(AngularGradient(colors: OrbColor.allCases.dropFirst()
                        .map { Color($0.tinta(for: nil).base) }, center: .center))
                } else {
                    Circle().fill(Color(color.tinta(for: nil).base))
                }
            }
            .frame(width: 18, height: 18)
            .padding(3)
            .overlay { Circle().strokeBorder(orbColor == color ? Palette.textPrimary : .clear, lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
        .help(Text(color.name))
        .accessibilityLabel(Text(color.name))
        .accessibilityAddTraits(orbColor == color ? .isSelected : [])
    }
}
