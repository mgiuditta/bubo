#if DEBUG
import SwiftUI

/// The debug panel: sets the Orb's Stato, Variante and provider and shows what one frame costs.
struct OrbDebugView: View {
    /// The identifier of the debug panel's window.
    static let windowID = "orb-debug"

    /// The bundled Catalogo, loaded once.
    private static let catalogo = Result { try Catalogo(bundle: .main) }

    @Bindable var controls: OrbControls

    var body: some View {
        Form {
            Picker("Stato", selection: $controls.state) {
                ForEach(OrbState.allCases) { state in
                    Text(state.title).tag(state)
                }
            }
            .pickerStyle(.radioGroup)

            switch Self.catalogo {
            case .success(let catalogo):
                Picker("Variante", selection: $controls.variante) {
                    Text("Blob").tag(Variante?.none)
                    ForEach(catalogo.varianti) { variante in
                        Text(variante.label).tag(Optional(variante))
                    }
                }
            case .failure(let error):
                LabeledContent("Variante") {
                    Text("Catalogo non valido: \(String(describing: error))")
                        .foregroundStyle(.red)
                }
            }

            Picker("Fornitore", selection: $controls.provider) {
                ForEach(Provider.allCases) { provider in
                    Text(verbatim: provider.name).tag(Optional(provider))
                }
                Text("Fuori elenco").tag(Provider?.none)
            }

            Section("Misure del Panel") {
                if let reading = controls.frameReading {
                    LabeledContent("fps") {
                        Text(reading.framesPerSecond, format: .number.precision(.fractionLength(1)))
                    }
                    if let gpuTime = reading.gpuTime {
                        LabeledContent("GPU per frame") {
                            Text(Measurement(value: gpuTime * 1000, unit: UnitDuration.milliseconds),
                                 format: .measurement(width: .abbreviated,
                                                      numberFormatStyle: .number.precision(.fractionLength(2))))
                        }
                        LabeledContent("GPU a 60 fps") {
                            Text(gpuTime * 60, format: .percent.precision(.fractionLength(1)))
                        }
                    }
                } else {
                    Text("In attesa del primo frame del Panel.")
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
        }
        .formStyle(.grouped)
        .frame(minWidth: 320)
    }
}

#Preview {
    OrbDebugView(controls: OrbControls())
}
#endif
