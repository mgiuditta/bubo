import Foundation

/// Finds the possible secrets of a Sessione before a Consegna (spec 24, Scanner), for the user to decide one by one.
///
/// Three sources: the rules of gitleaks with a known prefix; values with high entropy next to a key word, the
/// `generic-api-key` rule of gitleaks; the `NAME=value` lines of the `.env` files the Sessione read. It only
/// **reports**: no scanner finds everything, and the obligatory preview of what goes out is the real guarantee.
///
/// The rules come from `RegoleGitleaks.json`, made by `scripts/update-gitleaks-rules.sh` from gitleaks (MIT), with
/// the version written in the file. A result never shows its value: only ``Finding/maskedExcerpt``.
nonisolated struct SecretScanner: Sendable {
    /// Where a possible secret was found.
    struct Location: Hashable, Sendable {
        /// The file name: ``SessionFiles/transcriptName``, a subagent, its metadata or a tool result.
        var file: String
        /// The line, from 1.
        var line: Int
        /// The `uuid` of the transcript line, to show it in the conversation.
        var lineID: String?
    }

    /// A text to scan, and where it starts.
    struct Document: Sendable {
        var text: String
        var location: Location

        /// Where `value` first appears in the text, or `nil` if it does not.
        func location(of value: String) -> Location? {
            guard let range = text.range(of: value) else { return nil }
            var location = location
            location.line += text[..<range.lowerBound].count(where: \.isNewline)
            return location
        }
    }

    /// Which of the three sources found a secret.
    enum Source: Sendable {
        /// A gitleaks rule with a prefix the service gives its keys.
        case knownPrefix
        /// A value with high entropy next to a word such as `token`, `secret`, `password`, `key`.
        case keywordEntropy
        /// A `NAME=value` line of a `.env` file read in the Sessione.
        case envFile
    }

    /// One possible secret, once however many times it appears.
    struct Finding: Identifiable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        /// The gitleaks rule, or `env:NAME` for a `.env` line.
        let ruleID: String
        let source: Source
        /// The secret itself: it goes in ``TranscriptCleaner`` when the user picks Togli, never in a log.
        let value: String
        /// Every place it appears, in the order of the files.
        var locations: [Location]

        var id: String { ruleID + ":" + maskedExcerpt + ":\(value.hashValue)" }

        /// The first 4 characters and `…`: what the foglio di Consegna shows.
        var maskedExcerpt: String { String(value.prefix(4)) + "…" }

        /// How many characters the value has.
        var length: Int { value.count }

        var description: String { "\(ruleID) \(maskedExcerpt) (\(length)) × \(locations.count)" }
        var debugDescription: String { description }
        var customMirror: Mirror {
            Mirror(self, children: ["ruleID": ruleID, "maskedExcerpt": maskedExcerpt, "length": length,
                                    "locations": locations], displayStyle: .struct)
        }
    }

    /// The rules as `scripts/update-gitleaks-rules.sh` writes them.
    struct Configuration: Decodable, Sendable {
        struct Allowlist: Decodable, Sendable {
            var regexTarget: String
            var regexes: [String]
            var stopwords: [String]
        }

        struct Rule: Decodable, Sendable {
            var id: String
            var regex: String
            var secretGroup: Int
            var entropy: Double
            var keywords: [String]
            var allowlists: [Allowlist]
        }

        var version: String
        var allowlist: Allowlist
        var rules: [Rule]
    }

    /// The rules in the app's bundle, or `nil` when the file is missing.
    static let bundled: SecretScanner? = {
        guard let url = Bundle.main.url(forResource: "RegoleGitleaks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(Configuration.self, from: data)
        else { return nil }
        return SecretScanner(configuration: configuration)
    }()

    /// The gitleaks version the rules come from.
    let version: String
    /// The rules whose expression does not compile with `NSRegularExpression`, by id.
    let skippedRules: [String]
    private let rules: [Rule]
    private let allowlist: Allowlist

    /// Creates a scanner with the rules of `configuration`.
    init(configuration: Configuration) {
        version = configuration.version
        allowlist = Allowlist(configuration.allowlist)
        var rules: [Rule] = []
        var skipped: [String] = []
        for rule in configuration.rules {
            if let compiled = Rule(rule) { rules.append(compiled) } else { skipped.append(rule.id) }
        }
        self.rules = rules
        skippedRules = skipped
    }

    // MARK: Scanning

    /// The possible secrets of `session`: transcript, subagent, their metadata and tool results.
    func scan(_ session: SessionFiles) -> [Finding] {
        scan(Self.documents(of: session), envValues: Self.envValues(in: session))
    }

    /// The possible secrets of `documents`, plus `envValues` (`NAME` → value) wherever they appear.
    func scan(_ documents: [Document], envValues: [(name: String, value: String)] = []) -> [Finding] {
        // The `.env` lines first: the name they have says more than a generic rule.
        var found: [(value: String, ruleID: String, source: Source)] = envValues.map {
            ($0.value, "env:\($0.name)", .envFile)
        }
        for document in documents {
            let lowercased = document.text.lowercased()
            for rule in rules where rule.applies(to: lowercased) {
                for secret in rule.secrets(in: document.text) where !allowlist.allows(secret, match: secret, line: secret) {
                    found.append((secret, rule.id, rule.id == "generic-api-key" ? .keywordEntropy : .knownPrefix))
                }
            }
        }

        // One result per value; a value inside a known-prefix one is the same secret seen by a looser rule.
        let prefixed = found.filter { $0.source == .knownPrefix }.map(\.value)
        var findings: [Finding] = []
        var seen: Set<String> = []
        for entry in found where seen.insert(entry.value).inserted {
            if entry.source != .knownPrefix,
               prefixed.contains(where: { $0 != entry.value && ($0.contains(entry.value) || entry.value.contains($0)) }) {
                continue
            }
            let locations = documents.compactMap { $0.location(of: entry.value) }
            findings.append(Finding(ruleID: entry.ruleID, source: entry.source, value: entry.value,
                                    locations: Self.unique(locations)))
        }
        return findings
    }

    // MARK: Documents

    /// Every string of every file of `session`, with where it is.
    static func documents(of session: SessionFiles) -> [Document] {
        var documents: [Document] = []
        for (name, content) in session.jsonlFiles {
            for (index, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where !line.isEmpty {
                guard let value = try? JSONValue.decoding(line: line) else { continue }
                let location = Location(file: name, line: index + 1, lineID: value["uuid"]?.string)
                documents += value.strings.map { Document(text: $0, location: location) }
            }
        }
        for (name, content) in session.subagentMetadata.sorted(by: { $0.key < $1.key }) {
            documents.append(Document(text: content, location: Location(file: name, line: 1)))
        }
        // A tool result whole, so a private key over many lines stays one match.
        for (name, content) in session.toolResults.sorted(by: { $0.key < $1.key }) {
            documents.append(Document(text: content, location: Location(file: name, line: 1)))
        }
        return documents
    }

    /// The `NAME=value` lines of the `.env` files a tool read in `session`: what the tool gave back to a call whose
    /// input names a `.env` file.
    static func envValues(in session: SessionFiles) -> [(name: String, value: String)] {
        var values: [(name: String, value: String)] = []
        for (_, content) in session.jsonlFiles {
            let lines = content.split(separator: "\n").compactMap { try? JSONValue.decoding(line: $0) }
            var envCalls: Set<String> = []
            for line in lines {
                for block in blocks(of: line) where block["type"]?.string == "tool_use" {
                    if let id = block["id"]?.string, block["input"]?.strings.contains(where: names(envFile:)) == true {
                        envCalls.insert(id)
                    }
                }
            }
            guard !envCalls.isEmpty else { continue }
            for line in lines {
                for block in blocks(of: line)
                where block["type"]?.string == "tool_result" && envCalls.contains(block["tool_use_id"]?.string ?? "") {
                    for text in block["content"]?.strings ?? [] { values += envAssignments(in: text) }
                }
            }
        }
        return values
    }

    /// The `NAME=value` assignments of a `.env` file's text, also with the line numbers `Read` puts in front.
    static func envAssignments(in text: String) -> [(name: String, value: String)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let match = line.wholeMatch(of: #/\s*(?:\d+[→\t])?\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_.]*)\s*=\s*(.*?)\s*/#)
            else { return nil }
            var value = String(match.2)
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            // Ports, flags, empty values and secrets already taken out are not secrets to decide.
            let isPlain = value.count < 4 || Double(value) != nil || value == TranscriptCleaner.secretPlaceholder
                || ["true", "false", "yes", "no", "on", "off"].contains(value.lowercased())
            return isPlain ? nil : (String(match.1), value)
        }
    }

    private static func blocks(of line: JSONValue) -> [JSONValue] {
        guard case let .array(blocks) = line["message"]?["content"] else { return [] }
        return blocks
    }

    private static func names(envFile text: String) -> Bool {
        text.contains(#/(?:^|[\s\/'"=])\.env(?:\.[A-Za-z0-9_-]+)?(?:$|[\s'";])/#)
    }

    private static func unique(_ locations: [Location]) -> [Location] {
        var seen: Set<Location> = []
        return locations.filter { seen.insert($0).inserted }
    }
}

// MARK: - Rules

extension SecretScanner {
    /// A gitleaks rule, compiled.
    nonisolated private struct Rule: Sendable {
        let id: String
        let regex: NSRegularExpression
        let secretGroup: Int
        let entropy: Double
        let keywords: [String]
        let allowlists: [Allowlist]

        init?(_ rule: Configuration.Rule) {
            guard let regex = try? NSRegularExpression(pattern: rule.regex) else { return nil }
            self.regex = regex
            id = rule.id
            secretGroup = rule.secretGroup
            entropy = rule.entropy
            keywords = rule.keywords.map { $0.lowercased() }
            allowlists = rule.allowlists.map(Allowlist.init)
        }

        /// Whether the text, lowercased, has one of the rule's key words; gitleaks runs a rule only then.
        func applies(to lowercased: String) -> Bool {
            keywords.isEmpty || keywords.contains { lowercased.contains($0) }
        }

        /// The secrets the rule finds in `text`, as gitleaks takes them.
        func secrets(in text: String) -> [String] {
            let nsText = text as NSString
            return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { result in
                let match = nsText.substring(with: result.range)
                // The secret group, or else the first group that matched, or else the whole match.
                var range = secretGroup > 0 && secretGroup < result.numberOfRanges ? result.range(at: secretGroup)
                    : NSRange(location: NSNotFound, length: 0)
                if range.location == NSNotFound {
                    range = (1..<max(result.numberOfRanges, 1)).lazy.map { result.range(at: $0) }
                        .first { $0.location != NSNotFound && $0.length > 0 } ?? result.range
                }
                let secret = nsText.substring(with: range)
                if entropy > 0 {
                    guard Self.shannonEntropy(of: secret) > entropy else { return nil }
                    if id.hasPrefix("generic"), !secret.contains(where: \.isWholeNumber) { return nil }
                }
                let line = nsText.substring(with: nsText.lineRange(for: result.range))
                return allowlists.contains { $0.allows(secret, match: match, line: line) } ? nil : secret
            }
        }

        /// The Shannon entropy of `text`, in bits per character.
        static func shannonEntropy(of text: String) -> Double {
            guard !text.isEmpty else { return 0 }
            let counts = Dictionary(text.map { ($0, 1) }, uniquingKeysWith: +)
            let total = Double(text.count)
            return counts.values.reduce(0) { entropy, count in
                let frequency = Double(count) / total
                return entropy - frequency * log2(frequency)
            }
        }
    }

    /// What gitleaks lets through although a rule matched it.
    nonisolated private struct Allowlist: Sendable {
        enum Target: Sendable { case secret, match, line }

        let target: Target
        let regexes: [NSRegularExpression]
        let stopwords: [String]

        init(_ allowlist: Configuration.Allowlist) {
            target = switch allowlist.regexTarget {
            case "match": .match
            case "line": .line
            default: .secret
            }
            regexes = allowlist.regexes.compactMap { try? NSRegularExpression(pattern: $0) }
            stopwords = allowlist.stopwords.map { $0.lowercased() }
        }

        func allows(_ secret: String, match: String, line: String) -> Bool {
            let lowercased = secret.lowercased()
            if stopwords.contains(where: lowercased.contains) { return true }
            let text = switch target {
            case .secret: secret
            case .match: match
            case .line: line
            }
            let range = NSRange(text.startIndex..., in: text)
            return regexes.contains { $0.firstMatch(in: text, range: range) != nil }
        }
    }
}
