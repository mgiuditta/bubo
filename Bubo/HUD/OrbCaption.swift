import SwiftUI

/// The line under the Orb while a Domanda is under way: the Variante it morphs into and the Tinta it takes.
struct OrbCaption: View {
    let forecast: IntakePipeline.Forecast

    var body: some View {
        Text(text)
            .font(Typography.body(size: 13))
            .foregroundStyle(Palette.textSecondary)
            .accessibilityIdentifier("orb.caption")
    }

    private var text: LocalizedStringResource {
        // Four whole sentences, so a translator sees each one complete.
        switch (forecast.variante.map { String(localized: $0.label) }, forecast.provider?.name) {
        case let (variante?, provider?):
            LocalizedStringResource("Variante \(variante) · Tinta \(provider)", comment: Self.comment)
        case let (variante?, nil):
            LocalizedStringResource("Variante \(variante) · Tinta neutra", comment: Self.comment)
        case let (nil, provider?):
            LocalizedStringResource("Blob · Tinta \(provider)", comment: Self.comment)
        case (nil, nil):
            LocalizedStringResource("Blob · Tinta neutra", comment: Self.comment)
        }
    }

    private static let comment: StaticString = """
        Line under the Orb during a Domanda. Variante and Blob are the Orb's shape, Tinta the provider's colour; \
        the provider is a brand and is never translated.
        """
}

#Preview {
    OrbCaption(forecast: IntakePipeline.Forecast(variante: nil, provider: .anthropic))
        .padding()
        .background(Palette.ink)
}
