import SwiftUI

/// The search by meaning of the Indice: until the model is downloaded, with the user's consent, it searches only by words.
struct SemanticSearchSettingsSection: View {
    @Environment(SemanticSearch.self) private var search

    var body: some View {
        Section {
            switch search.phase {
            case .wordsOnly:
                Text("Ora l'Indice cerca solo per parole.")
                Button("Scarica il modello (\(TextEmbeddingModel.standard.size.formatted(.byteCount(style: .file))))") {
                    search.download(.standard)
                }
            case let .downloading(model, received):
                // A bar that always says how far it got, not a spinner (spec 27).
                Gauge(value: Double(received), in: 0...Double(model.size)) {
                    Text("Scarico \(model.name)…")
                } currentValueLabel: {
                    Text("\(received.formatted(.byteCount(style: .file))) di \(model.size.formatted(.byteCount(style: .file)))")
                }
                .gaugeStyle(.linearCapacity)
                Button("Annulla") { search.cancelDownload() }
            case let .ready(model):
                LabeledContent("Modello") {
                    Text(verbatim: model.name)
                }
                Text("L'Indice cerca per parole e per significato.")
                HStack {
                    if model == .standard {
                        Button("Passa alla qualità alta (\(TextEmbeddingModel.highQuality.size.formatted(.byteCount(style: .file))))") {
                            search.download(.highQuality)
                        }
                    } else {
                        Button("Torna al modello standard (\(TextEmbeddingModel.standard.size.formatted(.byteCount(style: .file))))") {
                            search.download(.standard)
                        }
                    }
                    Button("Elimina il modello", role: .destructive) { search.removeModel() }
                }
            case let .failed(model, reason):
                Label("Non riesco a scaricare il modello: \(reason)", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
                Button("Riprova") { search.download(model) }
            }
        } header: {
            Text("Ricerca per significato")
        } footer: {
            Text("Il modello si scarica una volta da Hugging Face e poi lavora solo su questo Mac: le note non escono. Cambiare modello ricalcola l'Indice.")
        }
    }
}
