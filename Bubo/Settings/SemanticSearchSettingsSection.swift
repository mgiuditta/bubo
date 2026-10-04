import SwiftUI

/// How the Indice searches: by words, the default, or also by meaning once the user chooses to download a model.
struct SemanticSearchSettingsSection: View {
    @Environment(SemanticSearch.self) private var search

    var body: some View {
        Section {
            Picker("Ricerca", selection: Binding(get: { isByMeaning }, set: { choose(byMeaning: $0) })) {
                VStack(alignment: .leading) {
                    Text("Per parole")
                    Text("Trova le parole esatte: preciso su nomi e frasi, non trova i sinonimi. Niente da scaricare.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .tag(false)
                VStack(alignment: .leading) {
                    Text("Per significato")
                    Text("Capisce il senso anche con altre parole. Scarica un modello locale (\(TextEmbeddingModel.standard.size.formatted(.byteCount(style: .file)))) e usa GPU e batteria.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            switch search.phase {
            case .wordsOnly:
                EmptyView()
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
                if let pause = search.pause {
                    // A state, not an error: no warning color.
                    Label(pauseText(pause), systemImage: "pause.circle")
                        .foregroundStyle(Palette.textSecondary)
                        .font(.callout)
                }
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
                }
            case let .failed(model, reason):
                Label("Non riesco a scaricare il modello: \(reason)", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
                Button("Riprova") { search.download(model) }
            }
        } header: {
            Text("Ricerca")
        } footer: {
            Text("Il modello si scarica una volta da Hugging Face e poi lavora solo su questo Mac: le note non escono. Cambiare modello ricalcola l'Indice; tornare a Per parole lo elimina.")
        }
    }

    /// Whether the Indice searches, or is getting ready to search, by meaning.
    private var isByMeaning: Bool {
        switch search.phase {
        case .wordsOnly, .failed: false
        case .downloading, .ready: true
        }
    }

    /// Downloads the standard model to search by meaning, or stops searching by meaning and deletes the model.
    private func choose(byMeaning: Bool) {
        switch (byMeaning, search.phase) {
        case (true, .wordsOnly), (true, .failed): search.download(.standard)
        case (false, .downloading): search.cancelDownload()
        case (false, .ready): search.removeModel()
        default: break
        }
    }

    private func pauseText(_ pause: IndexPause) -> String {
        switch pause {
        case .lowPowerMode:
            String(localized: "In pausa con il Risparmio energetico: riprende da sola.")
        case .lowBattery:
            String(localized: "In pausa con la batteria sotto il \(EnergyState.minimumBatteryLevel.formatted(.percent)): riprende da sola.")
        }
    }
}
