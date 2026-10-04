import Foundation

/// Takes keys, tokens, passwords and private keys out of a text, putting ``replacement`` in their place.
///
/// Local and deterministic: nothing leaves the Mac to decide what is a secret. It errs on the side of removing: a
/// value next to a word such as `password` or `token` goes, even when it was not one.
nonisolated struct SecretFilter: Sendable {
    /// What a secret becomes.
    static let replacement = "[rimosso]"

    /// Creates the filter.
    init() {}

    /// Returns `text` with every secret replaced by ``replacement``.
    func redacting(_ text: String) -> String {
        let removed = Self.replacement
        return text
            // Private keys in PEM, the whole block, also when its end was cut.
            .replacing(#/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|\z)/#,
                       with: removed)
            // Anthropic, OpenAI and the other `sk-` keys.
            .replacing(#/\bsk-[A-Za-z0-9_\-]{16,}/#, with: removed)
            // GitHub tokens.
            .replacing(#/\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})/#, with: removed)
            // AWS access key ids.
            .replacing(#/\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/#, with: removed)
            // Google API keys.
            .replacing(#/\bAIza[0-9A-Za-z_\-]{30,}/#, with: removed)
            // Slack tokens.
            .replacing(#/\bxox[abposr]-[A-Za-z0-9\-]{10,}/#, with: removed)
            // JSON Web Tokens.
            .replacing(#/\beyJ[A-Za-z0-9_\-]{8,}\.eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}/#, with: removed)
            // `Authorization: Bearer …` and the like.
            .replacing(#/(?i)\b(bearer|basic|token)\s+[A-Za-z0-9._~+\/=\-]{16,}/#) { "\($0.1) \(removed)" }
            // The password in a URL: `scheme://user:password@host`.
            .replacing(#/(:\/\/[^\/\s:@]+):[^\/\s@]+@/#) { "\($0.1):\(removed)@" }
            // `API_KEY=value` and `password: value`, when the name says it holds a secret; camelCase names are code.
            .replacing(#/\b((?:[A-Z0-9_.\-]*(?:PASSWORD|PASSWD|PWD|SECRET|TOKEN|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY|CREDENTIALS?)[A-Z0-9_.\-]*|[a-z0-9_.\-]*(?:password|passwd|pwd|secret|token|api[_\-]?key|access[_\-]?key|private[_\-]?key|credentials?)[a-z0-9_.\-]*)["']?\s*[:=]\s*["']?)[^\s"'`,;\[]{6,}/#) {
                "\($0.1)\(removed)"
            }
            // "la password del database è: …": soon after, on the same line, a word no language writes: with letters
            // and digits or symbols, or with a capital after a small letter.
            .replacing(#/(?i)\b(password|passwd|pwd|passphrase|secret|token)\b([^\n]{0,40}?[\s:="'])(?=[^\s"'`]*[A-Za-z])(?-i:(?=[^\s"'`]*(?:[0-9!$%&#@*+?^~]|[a-z][^\s"'`]*[A-Z])))[^\s"'`,;\[]{8,}/#) {
                "\($0.1)\($0.2)\(removed)"
            }
    }

    /// Whether `text` holds a secret the filter would remove.
    func containsSecret(_ text: String) -> Bool {
        redacting(text) != text
    }
}
