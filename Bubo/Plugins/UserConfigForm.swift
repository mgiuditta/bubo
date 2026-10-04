import SwiftUI
import UniformTypeIdentifiers

/// The Impostazioni sheet of a plugin: one field per option of its `userConfig`, secrets in a password field, saved
/// with `claude plugin configure --values-stdin` (spec 20, Fogli).
///
/// The values reach `claude` only on its standard input: never in its arguments, the log or Bubo's files. A secret is
/// never shown: its field starts empty, and left empty it keeps the one saved.
struct UserConfigForm: View {
    let entry: PluginEntry
    let catalog: PluginCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var options: PluginOptions?
    @State private var edited: [String: String] = [:]
    @State private var failure: Text?
    @State private var saving: Task<Void, Never>?
    /// The option whose file or folder is being chosen.
    @State private var choosing: PluginOptions.Option?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Impostazioni di \(entry.displayName)")
                .font(Typography.body(size: 15, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let options {
                Form {
                    ForEach(options.options) { option in
                        field(for: option, in: options)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            } else if failure == nil {
                LoadingLabel("Leggo le impostazioni…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            if let failure {
                failure
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if saving != nil {
                    LoadingLabel("Salvo…")
                }
                Spacer()
                Button("Annulla", role: .cancel) {
                    saving?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Salva", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(options == nil || saving != nil)
            }
        }
        .padding(Spacing.large)
        .frame(width: 480)
        .frame(minHeight: 240, maxHeight: 620)
        .task { await load() }
        .fileImporter(isPresented: isChoosing, allowedContentTypes: choosing?.kind == .directory ? [.folder] : [.item]) { result in
            if let option = choosing, case let .success(url) = result {
                edited[option.id] = url.path
            }
            choosing = nil
        }
    }

    @ViewBuilder
    private func field(for option: PluginOptions.Option, in options: PluginOptions) -> some View {
        let value = Binding { edited[option.id] ?? "" } set: { edited[option.id] = $0 }
        Group {
            switch option.kind {
            case .boolean:
                Toggle(isOn: Binding { value.wrappedValue == "true" } set: { value.wrappedValue = $0 ? "true" : "false" }) {
                    title(of: option)
                }
            case _ where !option.choices.isEmpty:
                Picker(selection: value) {
                    if !option.choices.contains(value.wrappedValue) {
                        Text("Nessun valore").tag(value.wrappedValue)
                    }
                    ForEach(option.choices, id: \.self) { choice in
                        Text(verbatim: choice).tag(choice)
                    }
                } label: {
                    title(of: option)
                }
            case _ where option.isSensitive:
                SecureField(text: value, prompt: options.configured.contains(option.id) ? Text("Valore già salvato") : nil) {
                    title(of: option)
                }
            case .directory, .file:
                LabeledContent {
                    HStack {
                        TextField(text: value, prompt: nil) { title(of: option) }
                            .labelsHidden()
                        Button("Scegli…") { choosing = option }
                    }
                } label: {
                    title(of: option)
                }
            case .string, .number:
                TextField(text: value, prompt: nil) {
                    title(of: option)
                }
            }
        }
        .disabled(saving != nil)
    }

    private func title(of option: PluginOptions.Option) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            if option.isRequired {
                Text("\(option.title) (da compilare)")
            } else {
                Text(verbatim: option.title)
            }
            if !option.summary.isEmpty {
                Text(verbatim: option.summary)
                    .font(Typography.body(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private var isChoosing: Binding<Bool> {
        Binding { choosing != nil } set: { if !$0 { choosing = nil } }
    }

    private func load() async {
        do {
            let read = try await catalog.options(of: entry.id)
            edited = read.values
            options = read
        } catch is CancellationError {
            return
        } catch let error as PluginCLIError {
            failure = Text(error.message)
        } catch {
            failure = Text(verbatim: error.localizedDescription)
        }
    }

    private func save() {
        guard let options else { return }
        // `--values-stdin` takes single-line strings only.
        if let broken = options.options.first(where: {
            (edited[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).contains(where: \.isNewline)
        }) {
            failure = Text("\(broken.title) non può andare a capo. Scrivilo su una riga sola.")
            return
        }
        let values = options.changes(in: edited)
        guard !values.values.isEmpty else {
            dismiss()
            return
        }
        failure = nil
        saving = Task {
            defer { saving = nil }
            do {
                let result = try await catalog.perform(.configure(entry.id, values: values))
                if result.succeeded {
                    dismiss()
                } else {
                    failure = Text(verbatim: result.message)
                }
            } catch is CancellationError {
                return
            } catch let error as PluginCLIError {
                failure = Text(error.message)
            } catch {
                failure = Text(verbatim: error.localizedDescription)
            }
        }
    }
}
