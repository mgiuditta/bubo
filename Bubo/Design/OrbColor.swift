import Foundation
import SwiftUI

/// The colour the user gives the Orb: by default it follows the provider that answers, or it stays on one Tinta.
///
/// The fixed colours reuse the providers' Tinte, already balanced for the shader on dark and on light.
nonisolated enum OrbColor: String, CaseIterable, Identifiable {
    case automatic, terracotta, amber, green, teal, blue, violet, pink, silver

    static let defaultsKey = "orbColor"

    var id: Self { self }

    /// The colour saved in Impostazioni › Aspetto; automatic when none is.
    static var current: OrbColor {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(OrbColor.init(rawValue:)) ?? .automatic
    }

    /// The Tinta the Orb takes on while `provider` answers.
    func tinta(for provider: Provider?) -> Tinta {
        switch self {
        case .automatic: Tinta(for: provider)
        case .terracotta: .anthropic
        case .amber: .mistral
        case .green: .deepSeek
        case .teal: .openAI
        case .blue: .google
        case .violet: .alibaba
        case .pink: .cohere
        case .silver: .xAI
        }
    }

    /// The name shown in Impostazioni.
    var name: LocalizedStringResource {
        switch self {
        case .automatic: "Automatico"
        case .terracotta: "Terracotta"
        case .amber: "Ambra"
        case .green: "Verde"
        case .teal: "Acqua"
        case .blue: "Blu"
        case .violet: "Viola"
        case .pink: "Rosa"
        case .silver: "Argento"
        }
    }
}
