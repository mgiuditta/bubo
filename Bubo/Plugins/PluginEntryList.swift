import SwiftUI

/// The middle column of the Plugin window: the entries of the sidebar item, or the search results by Marketplace.
struct PluginEntryList: View {
    let sections: [PluginSection]
    /// What the list says when it has nothing and nobody is searching.
    let emptyTitle: LocalizedStringKey
    let isLoading: Bool
    let isSearching: Bool
    let isListingUnavailable: Bool
    /// The plugins `claude` failed to load.
    let failing: Set<PluginID>
    let marketplaces: [Marketplace]
    let officialCache: OfficialCatalogCache?
    @Binding var selection: PluginID?
    /// Asks `claude` for the list again.
    let retry: () -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top) {
                if isListingUnavailable {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Non riesco a chiedere a claude l'elenco dei plugin: mostro quello che c'è nei file.")
                            .font(Typography.body(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Riprova", action: retry)
                            .controlSize(.small)
                    }
                    .padding(Spacing.xSmall)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            LoadingLabel("Leggo i plugin…")
        } else if sections.isEmpty {
            if isSearching {
                ContentUnavailableView.search
            } else {
                ContentUnavailableView(emptyTitle, systemImage: "puzzlepiece.extension")
            }
        } else {
            List(selection: $selection) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            PluginRow(entry: entry, failed: failing.contains(entry.id), marketplace: marketplaces.first { $0.name == entry.id.marketplace },
                                      officialCache: officialCache)
                                .tag(entry.id)
                        }
                    } header: {
                        if let marketplace = section.marketplace {
                            Text(verbatim: marketplace)
                        }
                    }
                }
            }
        }
    }
}
