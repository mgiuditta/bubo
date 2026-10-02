import SwiftUI

/// The trust label of an entry not installed: "solo testo", "esegue codice" or "componenti sconosciuti".
///
/// The caller colors it with the secondary text color: no colored background, no Lume (design system).
struct PluginTrustLabel: View {
    let trust: PluginTrust

    var body: some View {
        Label {
            switch trust {
            case .textOnly: Text("solo testo")
            case .runsCode: Text("esegue codice")
            case .unknown: Text("componenti sconosciuti")
            }
        } icon: {
            switch trust {
            case .textOnly: Image(systemName: "doc.plaintext")
            case .runsCode: Image(systemName: "terminal")
            case .unknown: Image(systemName: "questionmark.circle")
            }
        }
        .font(Typography.body(size: 11))
    }
}
