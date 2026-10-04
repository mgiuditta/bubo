import Foundation
import os

/// The prices Bubo estimates the Spesa of OpenAI, Gemini and xAI with (spec 18, Prezzi): a snapshot of models.dev in
/// the bundle, refreshed at most once a day unless the user turns it off.
///
/// No price is written in the code. A model the table does not have is "senza prezzo": its turn counts only tokens.
/// Claude is priced by the SDK and OpenRouter by its answer, so neither is here.
@Observable
final class PriceTable {
    /// The table the app uses, kept in Bubo's Application Support folder once refreshed.
    static let shared = PriceTable(file: try? FileManager.default
        .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        .appending(path: "Bubo/Prezzi.json"))

    /// The address of the whole models.dev catalog: the feature's only network call.
    static let source = URL(string: "https://models.dev/api.json")!

    /// The prices in use.
    private(set) var snapshot: Snapshot

    /// Whether the table is refreshed from models.dev, at most once a day; on by default.
    var updatesDaily: Bool {
        didSet { defaults.set(updatesDaily, forKey: Self.updatesDailyKey) }
    }

    /// Creates a table that keeps its refreshed copy in `file`, starting from the newer of that copy and `bundled`.
    ///
    /// - Parameters:
    ///   - bundled: The snapshot shipped with the app; the one in Bubo's bundle when `nil`.
    ///   - source: Where the refresh downloads the catalog from; tests pass a stand-in server.
    ///   - session: The session of the refresh; tests pass one served by a stand-in server.
    ///   - defaults: Where the switch and the time of the last refresh are kept.
    init(file: URL?, bundled: Snapshot? = nil, source: URL = PriceTable.source,
         session: URLSession = URLSession(configuration: .ephemeral), defaults: UserDefaults = .standard) {
        self.file = file
        self.sourceURL = source
        self.session = session
        self.defaults = defaults
        updatesDaily = defaults.object(forKey: Self.updatesDailyKey) as? Bool ?? true
        let shipped = bundled ?? Self.bundled ?? Snapshot(date: .distantPast, etag: nil, providers: [:])
        let saved = file.flatMap { try? JSONDecoder.prices.decode(Snapshot.self, from: Data(contentsOf: $0)) }
        snapshot = saved.map { $0.date > shipped.date ? $0 : shipped } ?? shipped
    }

    @ObservationIgnored private let file: URL?
    @ObservationIgnored private let sourceURL: URL
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isUpdating = false

    private static let updatesDailyKey = "prices.updatesDaily"
    private static let lastCheckKey = "prices.lastCheck"

    /// The snapshot in Bubo's bundle, written by `scripts/update-prices.sh`.
    static let bundled: Snapshot? = {
        guard let url = Bundle.main.url(forResource: "Prezzi", withExtension: "json") else { return nil }
        do {
            return try JSONDecoder.prices.decode(Snapshot.self, from: Data(contentsOf: url))
        } catch {
            Logger.costs.error("Bundled prices unreadable: \(error)")
            return nil
        }
    }()

    /// Refreshes the table from models.dev when the user allows it and the last try is a day old or more.
    ///
    /// The request is a plain GET with the copy's `etag`: no key, no cookie, nothing of the user's. Offline, the table
    /// stays as it is.
    func updateIfDue(now: Date = .now) async {
        guard updatesDaily, !isUpdating else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date, now.timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        defaults.set(now, forKey: Self.lastCheckKey)
        var request = URLRequest(url: sourceURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpShouldHandleCookies = false
        if let etag = snapshot.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            switch http?.statusCode {
            case 304:
                snapshot.date = now
            case 200:
                snapshot = try await Self.reduced(data, date: now, etag: http?.value(forHTTPHeaderField: "ETag"))
            default:
                Logger.costs.notice("Prices not refreshed: status \(http?.statusCode ?? 0)")
                return
            }
            save()
        } catch {
            Logger.costs.notice("Prices not refreshed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The whole models.dev catalog cut down to the providers Bubo prices and to the models with a cost, as
    /// `scripts/update-prices.sh` cuts the bundled one.
    @concurrent static func reduced(_ catalog: Data, date: Date, etag: String?) async throws -> Snapshot {
        guard let all = try JSONSerialization.jsonObject(with: catalog) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        var providers: [String: Snapshot.Provider] = [:]
        for id in Snapshot.providerIDs {
            guard let provider = all[id] else { continue }
            let data = try JSONSerialization.data(withJSONObject: provider)
            var decoded = try JSONDecoder().decode(Snapshot.Provider.self, from: data)
            decoded.models = decoded.models.filter { $0.value.cost != nil }
            providers[id] = decoded
        }
        guard !providers.isEmpty else { throw CocoaError(.coderValueNotFound) }
        return Snapshot(date: date, etag: etag, providers: providers)
    }

    private func save() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.prices.encode(snapshot).write(to: file, options: .atomic)
        } catch {
            Logger.costs.error("Prices not saved: \(error)")
        }
    }
}

extension PriceTable {
    /// The prices of a few providers of models.dev, in its own format, with the day they were read.
    nonisolated struct Snapshot: Codable, Equatable, Sendable {
        /// The models.dev providers Bubo prices with the table.
        static let providerIDs = ["openai", "google", "xai"]

        /// One provider of models.dev, with its models by id.
        struct Provider: Codable, Equatable, Sendable {
            var models: [String: Model]
        }

        /// A model of models.dev; only its cost is kept.
        struct Model: Codable, Equatable, Sendable {
            var cost: Cost?
        }

        /// When models.dev last gave these prices: the day of the download, since the catalog carries no date.
        var date: Date
        /// The catalog's `etag`, to ask for it again only if it changed.
        var etag: String?
        var providers: [String: Provider]

        /// The cost of `model` at the models.dev provider `provider`; `nil` when the table does not have it.
        func cost(of model: String, at provider: String) -> Cost? {
            let models = providers[provider]?.models
            // Gemini's OpenAI-compatible endpoint also takes ids such as `models/gemini-2.5-pro`.
            let id = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
            return models?[id]?.cost
        }

        /// Whether the prices are more than 30 days old, so the line says which day they are from.
        func isOld(at now: Date = .now) -> Bool {
            now.timeIntervalSince(date) > 30 * 24 * 60 * 60
        }
    }

    /// What a model costs, in dollars per million tokens, as models.dev writes it.
    nonisolated struct Cost: Codable, Equatable, Sendable {
        /// The prices above a size of the context, such as Gemini's over 200,000 tokens.
        struct Tier: Codable, Equatable, Sendable {
            struct Threshold: Codable, Equatable, Sendable {
                var type: String
                var size: Int?
            }

            var input: Decimal?
            var output: Decimal?
            var cacheRead: Decimal?
            var tier: Threshold

            enum CodingKeys: String, CodingKey {
                case input, output, tier
                case cacheRead = "cache_read"
            }
        }

        var input: Decimal?
        var output: Decimal?
        var cacheRead: Decimal?
        var cacheWrite: Decimal?
        var tiers: [Tier]?

        enum CodingKeys: String, CodingKey {
            case input, output, tiers
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
        }

        /// The figure of a turn of `input` tokens, `cachedInput` of them read from the cache, and `output` tokens; `nil`
        /// when the table lacks a price the turn needs.
        func figure(input: Int, cachedInput: Int, output: Int) -> Decimal? {
            // Above a context threshold the whole turn takes that tier's prices.
            let tier = (tiers ?? []).filter { $0.tier.type == "context" && input > $0.tier.size ?? .max }
                .max { ($0.tier.size ?? 0) < ($1.tier.size ?? 0) }
            guard let inputPrice = tier?.input ?? self.input, let outputPrice = tier?.output ?? self.output else {
                return nil
            }
            let cached = min(max(cachedInput, 0), input)
            let cachePrice = tier?.cacheRead ?? cacheRead ?? inputPrice
            let total = Decimal(input - cached) * inputPrice + Decimal(cached) * cachePrice
                + Decimal(output) * outputPrice
            return total / 1_000_000
        }
    }
}

private extension JSONDecoder {
    nonisolated static var prices: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    nonisolated static var prices: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}
