import Foundation

/// A server that speaks OpenAI Chat Completions, which can answer a Domanda (spec 10, Fornitori delle Domande).
///
/// What it is never holds a secret: its key stays in the keychain, under `keychainAccount`.
nonisolated struct OpenAICompatibleEndpoint: Codable, Hashable, Identifiable, Sendable {
    /// Who runs the server; the known ones have a fixed address and name.
    enum Kind: String, Codable, Sendable {
        case openAI, gemini, openRouter, ollama, lmStudio, custom
    }

    /// Stable across launches: the kind for the known ones, a random id for a custom endpoint.
    let id: String
    let kind: Kind
    /// The name in "Rifai con…" and in the settings; a brand, or what the user called a custom endpoint.
    var name: String
    /// The address `chat/completions` hangs off, such as `https://api.openai.com/v1`.
    var baseURL: URL
    /// The model id the endpoint answers with, such as `gpt-5-mini`; empty until the user writes it.
    var model: String
    /// Gemini only: the user confirmed the key's project has billing on, the only Gemini allowed in the EEA.
    ///
    /// No API says whether a key is on the free tier, so it is the user's word (preflight of #92).
    var confirmsBilling = false

    /// The endpoints Bubo knows, with no model chosen yet.
    static let known: [Self] = [
        Self(id: "openai", kind: .openAI, name: "OpenAI", baseURL: URL(string: "https://api.openai.com/v1")!, model: ""),
        Self(id: "gemini", kind: .gemini, name: "Gemini",
             baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!, model: ""),
        Self(id: "openrouter", kind: .openRouter, name: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!,
             model: ""),
        // `localhost`, not 127.0.0.1: App Transport Security lets plain HTTP through only to a name.
        Self(id: "ollama", kind: .ollama, name: "Ollama", baseURL: URL(string: "http://localhost:11434/v1")!, model: ""),
        Self(id: "lmstudio", kind: .lmStudio, name: "LM Studio", baseURL: URL(string: "http://localhost:1234/v1")!,
             model: ""),
    ]

    /// A custom endpoint called `name` at `baseURL`, such as xAI's.
    static func custom(named name: String, at baseURL: URL) -> Self {
        Self(id: "custom-\(UUID().uuidString)", kind: .custom, name: name, baseURL: baseURL, model: "")
    }

    /// Whether the endpoint runs on this Mac, so the Domanda never leaves it: free, and no consent needed.
    var isOnMac: Bool {
        guard let host = baseURL.host() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    /// The provider whose Tinta the Orb takes while it answers; `nil` for the neutral Tinta.
    var provider: Provider? {
        switch kind {
        case .openAI: .openAI
        case .gemini: .google
        case .openRouter, .ollama, .lmStudio, .custom: Provider(named: name)
        }
    }

    /// The keychain account of the endpoint's key.
    var keychainAccount: String { "endpoint-\(id)" }

    /// Whether the endpoint cannot answer without a key: the cloud ones Bubo knows. A custom endpoint uses one only if
    /// saved, and the servers on the Mac ignore it.
    var requiresKey: Bool {
        kind == .openAI || kind == .gemini || kind == .openRouter
    }

    /// The full address of `chat/completions`.
    var chatCompletionsURL: URL {
        baseURL.appending(path: "chat/completions")
    }
}
