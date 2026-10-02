import Foundation

/// The CostLedger's turns of a period, grouped for the Costi window: rows, totals, the chart's points and the CSV.
///
/// Spesa, Valore a listino and Gratis never meet: each row, total and point has one unit, and the CSV keeps Spesa and
/// Valore a listino in columns of their own. The Quota is a share of the subscription, not a figure, and is not here.
struct CostHistory: Equatable {
    /// What the rows are grouped by.
    enum Grouping: String, CaseIterable, Identifiable, Sendable {
        case project, session, model, provider, period

        var id: Self { self }
    }

    /// How far back the turns go.
    enum Period: String, CaseIterable, Identifiable, Sendable {
        case week, month, quarter, year, all

        var id: Self { self }

        /// The first moment counted, `nil` for every turn.
        func start(endingAt now: Date, calendar: Calendar) -> Date? {
            let today = calendar.startOfDay(for: now)
            return switch self {
            case .week: calendar.date(byAdding: .day, value: -6, to: today)
            case .month: calendar.date(byAdding: .day, value: -29, to: today)
            case .quarter: calendar.date(byAdding: .day, value: -89, to: today)
            case .year: calendar.date(byAdding: .month, value: -11, to: calendar.dateInterval(of: .month, for: now)?.start ?? today)
            case .all: nil
            }
        }

        /// The span of one bar of the chart and of one row grouped by period: a day, or a month for a year and more.
        var bucket: Calendar.Component {
            switch self {
            case .week, .month, .quarter: .day
            case .year, .all: .month
            }
        }
    }

    /// The tokens of a row or a total.
    struct Tokens: Equatable, Sendable {
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0

        var total: Int { input + output + cacheRead + cacheWrite }

        mutating func add(_ tokens: TurnUsage.ModelTokens) {
            input += tokens.inputTokens
            output += tokens.outputTokens
            cacheRead += tokens.cacheReadTokens
            cacheWrite += tokens.cacheWriteTokens
        }
    }

    /// One group's turns of one unit and one origin, so every figure says where it comes from.
    struct Row: Equatable, Identifiable, Sendable {
        /// The group, the unit and the origin.
        var id: String
        /// The Progetto, Sessione, model or provider; for a period, the day or the month, formatted by the view.
        var group: String
        /// The start of the day or month, when grouped by period.
        var date: Date?
        var unit: CostUnit
        var origin: CostOrigin
        var amount = CostLedger.Amount()
        var tokens = Tokens()
        var turns = 0
        /// The latest day of the PriceTable's prices among the turns, for a figure priced with it.
        var priceDate: Date?
    }

    /// The figure of one bar of the chart: one unit, one day or month.
    struct Point: Equatable, Identifiable, Sendable {
        var date: Date
        var value: Decimal

        var id: Date { date }
    }

    /// The groups' rows, the largest figure first within each unit; by date when grouped by period.
    let rows: [Row]
    /// The total of each unit with turns in the period, never added to another unit.
    let totals: [CostUnit: CostLedger.Amount]
    /// The tokens of each unit with turns in the period.
    let tokens: [CostUnit: Tokens]
    /// The chart's bars of each unit with turns in the period, oldest first.
    let points: [CostUnit: [Point]]
    /// The span of one bar.
    let bucket: Calendar.Component

    /// Groups `entries` of `period`, ending at `now`, by `grouping`.
    ///
    /// - Parameter sessionTitle: The title of a Sessione still in Bubo; `nil` for one deleted.
    init(entries: [CostLedger.Entry], grouping: Grouping, period: Period, now: Date = .now,
         calendar: Calendar = .current, sessionTitle: (UUID) -> String? = { _ in nil }) {
        let start = period.start(endingAt: now, calendar: calendar)
        let counted = entries.filter { entry in start.map { entry.date >= $0 } ?? true }
        bucket = period.bucket
        var rows: [String: Row] = [:]
        var totals: [CostUnit: CostLedger.Amount] = [:]
        var tokens: [CostUnit: Tokens] = [:]
        var points: [CostUnit: [Date: Decimal]] = [:]
        var questionTitles: [UUID: String] = [:]
        for entry in counted {
            let usage = entry.usage
            let unit = usage.unit
            let day = calendar.dateInterval(of: period.bucket, for: entry.date)?.start ?? entry.date
            Self.add(usage.cost, of: usage, to: &totals[unit, default: .init()])
            for model in usage.models { tokens[unit, default: .init()].add(model) }
            points[unit, default: [:]][day, default: 0] += usage.cost ?? 0
            // Grouped by model, each model of the turn is a group with its share; otherwise the turn is one.
            let shares: [(key: String, group: String, models: [TurnUsage.ModelTokens], cost: Decimal?)] =
                switch grouping {
                case .model: usage.models.map { ($0.model, $0.model, [$0], $0.cost) }
                case .project:
                    [(entry.project?.path ?? "", entry.project?.lastPathComponent ?? String(localized: "Domande"),
                      usage.models, usage.cost)]
                case .provider: [(entry.provider ?? "Anthropic", entry.provider ?? "Anthropic", usage.models, usage.cost)]
                case .period:
                    [(day.formatted(.iso8601), day.formatted(.iso8601.year().month().day()), usage.models, usage.cost)]
                case .session:
                    [(entry.session.uuidString, Self.title(of: entry, sessionTitle: sessionTitle, questions: &questionTitles),
                      usage.models, usage.cost)]
                }
            for share in shares {
                let key = "\(share.key)|\(unit.rawValue)|\(usage.origin.rawValue)"
                var row = rows[key] ?? Row(id: key, group: share.group, date: grouping == .period ? day : nil,
                                           unit: unit, origin: usage.origin)
                Self.add(share.cost, of: usage, to: &row.amount)
                share.models.forEach { row.tokens.add($0) }
                row.turns += 1
                if let date = usage.priceDate { row.priceDate = max(row.priceDate ?? date, date) }
                rows[key] = row
            }
        }
        self.rows = rows.values.sorted { lhs, rhs in
            if let left = lhs.date, let right = rhs.date, left != right { return left < right }
            if lhs.unit != rhs.unit { return CostUnit.allCases.firstIndex(of: lhs.unit)! < CostUnit.allCases.firstIndex(of: rhs.unit)! }
            if lhs.amount.value != rhs.amount.value { return lhs.amount.value > rhs.amount.value }
            return lhs.id < rhs.id
        }
        self.totals = totals
        self.tokens = tokens
        self.points = points.mapValues { days in
            days.map { Point(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
        }
    }

    /// The rows as CSV, one line each, with Spesa and Valore a listino in separate columns, so adding up a column
    /// never mixes them.
    var csv: String {
        let header = "gruppo,unita,origine,spesa_usd,valore_listino_usd,incerta,incompleta,token_input,token_output,"
            + "token_cache_lettura,token_cache_scrittura,turni,data_tabella_prezzi"
        let lines = rows.map { row in
            let figure = row.origin == .unpriced ? "" : "\(row.amount.value)"
            return [
                Self.field(row.group), row.unit.rawValue, row.origin.rawValue,
                row.unit == .spesa ? figure : "", row.unit == .valoreListino ? figure : "",
                "\(row.amount.isUncertain)", "\(row.amount.isIncomplete)",
                "\(row.tokens.input)", "\(row.tokens.output)", "\(row.tokens.cacheRead)", "\(row.tokens.cacheWrite)",
                "\(row.turns)", row.priceDate?.formatted(.iso8601.year().month().day()) ?? "",
            ].joined(separator: ",")
        }
        return ([header] + lines).joined(separator: "\r\n") + "\r\n"
    }

    /// Adds `cost`, the whole turn `usage`'s or a model's share, to `amount`.
    private static func add(_ cost: Decimal?, of usage: TurnUsage, to amount: inout CostLedger.Amount) {
        amount.value += cost ?? 0
        amount.isUncertain = amount.isUncertain || usage.basis == .unknown
        // A model with no price has no figure by design: only a turn cut short misses one.
        amount.isIncomplete = amount.isIncomplete || !usage.isComplete || (cost == nil && usage.origin != .unpriced)
    }

    /// `text` as one CSV field, quoted when it holds a comma, a quote or a line break.
    private static func field(_ text: String) -> String {
        guard text.contains(where: { ",\"\r\n".contains($0) }) else { return text }
        return "\"" + text.replacing("\"", with: "\"\"") + "\""
    }

    /// The Sessione's title; for a Domanda, its first turn's day and time.
    private static func title(of entry: CostLedger.Entry, sessionTitle: (UUID) -> String?,
                              questions: inout [UUID: String]) -> String {
        guard entry.project == nil else {
            return sessionTitle(entry.session) ?? String(localized: "Sessione \(String(entry.session.uuidString.prefix(8)))")
        }
        if let title = questions[entry.session] { return title }
        let title = String(localized: "Domanda del \(entry.date.formatted(date: .abbreviated, time: .shortened))")
        questions[entry.session] = title
        return title
    }
}
