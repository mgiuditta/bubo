import SwiftUI

/// The detail of a plugin: name, Marketplace, version, state, what needs attention, its components, and at the
/// bottom Attiva or Disattiva (primary) and Disinstalla… (secondary), or Installa… when it is not installed.
struct PluginDetail: View {
    let entry: PluginEntry
    /// What puts the plugin in Da sistemare, gravest first.
    let problems: [PluginProblem]
    /// Everything the window shows, for the action of each problem.
    let snapshot: PluginSnapshot
    let marketplace: Marketplace?
    let officialCache: OfficialCatalogCache?
    let catalog: PluginCatalog
    /// Opens the Installa sheet.
    let install: () -> Void
    /// Opens the Disinstalla sheet.
    let uninstall: () -> Void
    @State private var inventory: PluginInventory?
    @State private var hasReadInventory = false
    @State private var failure: Text?
    /// Whether the installed plugin declares a `userConfig`, so it has Impostazioni.
    @State private var hasOptions = false
    /// The required options with no value saved.
    @State private var missingOptions: [PluginOptions.Option] = []
    @State private var isConfiguring = false

    /// What the inventory is read for: the entry, and whether the official cache has arrived.
    private struct InventoryKey: Equatable {
        var entry: PluginEntry
        var hasOfficialCache: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                header
                labels
                if !problems.isEmpty { problemList }
                if !missingOptions.isEmpty { missingOptionsBox }
                if !entry.summary.isEmpty {
                    Text(verbatim: entry.summary)
                        .font(Typography.body(size: 13))
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hasReadInventory {
                    if let inventory {
                        PluginInventoryList(inventory: inventory, isInstalled: entry.isInstalled)
                    } else {
                        Label("Componenti sconosciuti: può eseguire codice sul Mac", systemImage: "questionmark.circle")
                            .font(Typography.body(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                            .padding(Spacing.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.surface, in: .rect(cornerRadius: 8))
                    }
                }
                actions
            }
            .padding(Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: InventoryKey(entry: entry, hasOfficialCache: officialCache != nil)) {
            let read = await PluginInventory.inventory(of: entry, marketplace: marketplace, officialCache: officialCache)
            inventory = read
            hasReadInventory = true
        }
        // Read again when the Impostazioni sheet closes.
        .task(id: isConfiguring) {
            guard !isConfiguring else { return }
            await readOptions()
        }
        .sheet(isPresented: $isConfiguring) {
            UserConfigForm(entry: entry, catalog: catalog)
        }
    }

    /// Whether the plugin has Impostazioni, and which required ones have no value; nothing when `claude` cannot say.
    private func readOptions() async {
        guard entry.isInstalled,
              await PluginOptions.areDeclared(at: entry.installations.first { $0.installPath != nil }?.installPath)
        else { return }
        hasOptions = true
        missingOptions = (try? await catalog.options(of: entry.id))?.missingRequired ?? []
    }

    /// The box of the required Impostazioni with no value, with Configura….
    private var missingOptionsBox: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Label {
                Text("Impostazioni da compilare: \(missingOptions.map(\.title).formatted(.list(type: .and)))")
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Palette.danger)
                    .accessibilityLabel(Text("Errore"))
            }
            Button("Configura…") { isConfiguring = true }
                .buttonStyle(.borderedProminent)
        }
        .font(Typography.body(size: 12))
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: 8))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(verbatim: entry.displayName)
                .font(Typography.body(size: 20, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Spacing.xSmall) {
                if entry.id.isSynced {
                    Text("Sincronizzato da claude.ai")
                } else {
                    Text(verbatim: entry.id.marketplace)
                }
                if let version = entry.installations.first?.version ?? entry.version {
                    Text("Versione \(version)")
                }
            }
            .font(Typography.body(size: 12))
            .foregroundStyle(Palette.textSecondary)
        }
    }

    private var labels: some View {
        HStack(spacing: Spacing.small) {
            if entry.isInstalled {
                Text(entry.isEnabled ? "Attivo" : "Disattivato")
                ForEach(Array(Set(entry.installations.map(\.scope))).sorted { $0.rawValue < $1.rawValue }, id: \.self) { scope in
                    Text(scope.title)
                }
                if inventory?.runsOutsideSandbox == true {
                    OutsideSandboxLabel()
                }
            } else if hasReadInventory {
                PluginTrustLabel(trust: PluginInventory.trust(of: inventory))
            }
        }
        .font(Typography.body(size: 11))
        .foregroundStyle(Palette.textSecondary)
    }

    @ViewBuilder
    private var actions: some View {
        let isPending = catalog.pending.contains(entry.id)
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack(spacing: Spacing.small) {
                if !entry.isInstalled {
                    Button("Installa…", action: install)
                        .buttonStyle(.borderedProminent)
                } else if let scope = entry.switchScope {
                    Button(entry.isEnabled ? "Disattiva" : "Attiva") {
                        toggle(in: scope)
                    }
                    .buttonStyle(.borderedProminent)
                    if hasOptions {
                        Button("Impostazioni…") { isConfiguring = true }
                    }
                    Button("Disinstalla…", action: uninstall)
                        .foregroundStyle(Palette.danger)
                }
                if isPending {
                    LoadingLabel("Aspetto claude…")
                }
            }
            .disabled(isPending)
            if entry.isInstalled, entry.switchScope == nil {
                Text("Gestito dall'organizzazione")
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.textSecondary)
            }
            if let failure {
                failure
                    .font(Typography.body(size: 12))
                    .foregroundStyle(Palette.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Spacing.small)
    }

    /// Turns the plugin off, or on, in `scope`, and says why when `claude` refuses.
    private func toggle(in scope: PluginScope) {
        let command: PluginCommand = entry.isEnabled ? .disable(entry.id, scope: scope) : .enable(entry.id, scope: scope)
        failure = nil
        Task {
            do {
                let result = try await catalog.perform(command)
                if !result.succeeded { failure = Text(verbatim: result.message) }
            } catch is CancellationError {
                return
            } catch let error as PluginCLIError {
                failure = Text(error.message)
            } catch {
                failure = Text(verbatim: error.localizedDescription)
            }
        }
    }

    /// One box per problem, gravest first, each with one button.
    private var problemList: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                PluginProblemBox(problem: problem,
                                 remedy: PluginRemedy(problem: problem, entry: entry, snapshot: snapshot),
                                 catalog: catalog, install: install)
            }
        }
    }
}
