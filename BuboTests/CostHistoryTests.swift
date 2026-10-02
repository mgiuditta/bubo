import Foundation
import Testing
@testable import Bubo

@MainActor
struct CostHistoryTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    static func usage(_ mode: TurnUsage.Mode, _ cost: Decimal?, origin: CostOrigin = .listEstimate,
                      models: [(String, Decimal?)] = [("claude-sonnet-4-5", nil)]) -> TurnUsage {
        TurnUsage(mode: mode, cost: cost, basis: .list, isComplete: true, models: models.map { model, share in
            .init(model: model, inputTokens: 100, outputTokens: 10, cacheReadTokens: 5, cacheWriteTokens: 1,
                  thinkingTokens: 0, cost: share ?? cost)
        }, origin: origin)
    }

    /// A ledger with every unit and origin: Spesa, Valore a listino, Gratis, a price-table and an unpriced turn.
    static func mixedLedger() -> CostLedger {
        let ledger = CostLedger()
        let project = URL(filePath: "/tmp/bubo")
        let session = UUID()
        let question = UUID()
        ledger.record(usage(.apiKey, 0.5), turn: "t1", session: session, project: project, at: now.addingTimeInterval(-3_600))
        ledger.record(usage(.subscription, 1.25), turn: "t2", session: session, project: project,
                      at: now.addingTimeInterval(-86_400 * 3))
        ledger.record(usage(.apiKey, 0, origin: .free, models: [("llama3", 0)]), turn: "t3", question: question,
                      provider: "Ollama", at: now.addingTimeInterval(-60))
        ledger.record(usage(.apiKey, 0.03, origin: .reported, models: [("openai/gpt-5", 0.03)]), turn: "t4",
                      question: question, provider: "OpenRouter", at: now.addingTimeInterval(-120))
        ledger.record(usage(.apiKey, nil, origin: .unpriced, models: [("mystery", nil)]), turn: "t5",
                      question: question, provider: "Custom", at: now.addingTimeInterval(-180))
        ledger.record(usage(.subscription, 0.75, models: [("claude-opus-4-1", 0.5), ("claude-haiku-4-5", 0.25)]),
                      turn: "t6", session: session, project: project, at: now.addingTimeInterval(-86_400 * 10))
        return ledger
    }

    static func history(_ ledger: CostLedger, _ grouping: CostHistory.Grouping,
                        period: CostHistory.Period = .all) -> CostHistory {
        CostHistory(entries: ledger.entries, grouping: grouping, period: period, now: now, calendar: calendar)
    }

    @Test(arguments: CostHistory.Grouping.allCases)
    func noTotalRowOrBarMixesTwoUnits(grouping: CostHistory.Grouping) {
        let history = Self.history(Self.mixedLedger(), grouping)
        #expect(history.totals[.spesa]?.value == Decimal(string: "0.53"))
        #expect(history.totals[.valoreListino]?.value == 2)
        #expect(history.totals[.gratis]?.value == 0)
        for unit in CostUnit.allCases {
            let rows = history.rows.filter { $0.unit == unit }.reduce(Decimal(0)) { $0 + $1.amount.value }
            let bars = history.points[unit, default: []].reduce(Decimal(0)) { $0 + $1.value }
            #expect(rows == history.totals[unit]?.value ?? 0)
            #expect(bars == history.totals[unit]?.value ?? 0)
        }
    }

    /// A turn of the Cronologia CLI, as `CLIHistoryReader` reads it.
    static let commandLineEntry = CostLedger.Entry(
        id: "cli|msg|req", session: UUID(), project: URL(filePath: "/tmp/cli"), provider: "Anthropic",
        date: now.addingTimeInterval(-600), usage: usage(.commandLine, 0.4, origin: .priceTable))

    @Test func theCommandLineIsAUnitOfItsOwnAndCanBeFilteredBySource() throws {
        let entries = Self.mixedLedger().entries + [Self.commandLineEntry]
        func history(_ source: CostHistory.Source) -> CostHistory {
            CostHistory(entries: entries, grouping: .project, period: .all, source: source, now: Self.now,
                        calendar: Self.calendar)
        }
        let all = history(.all)
        #expect(all.totals[.rigaDiComando]?.value == 0.4)
        #expect(all.totals[.spesa]?.value == Decimal(string: "0.53"))
        #expect(all.totals[.valoreListino]?.value == 2)
        #expect(history(.bubo).totals[.rigaDiComando] == nil)
        #expect(history(.bubo).totals[.spesa]?.value == Decimal(string: "0.53"))
        #expect(Set(history(.commandLine).totals.keys) == [.rigaDiComando])
        #expect(history(.commandLine).rows.map(\.group) == ["cli"])
        // The CSV keeps the estimate in its own column, never in Spesa or Valore a listino.
        let line = try #require(all.csv.split(separator: "\r\n").first { $0.hasPrefix("cli,") })
        #expect(line.hasPrefix("cli,rigaDiComando,priceTable,,,0.4,"))
    }

    @Test(arguments: CostHistory.Grouping.allCases)
    func noCSVColumnMixesSpesaAndValoreAListino(grouping: CostHistory.Grouping) throws {
        let history = Self.history(Self.mixedLedger(), grouping)
        // The group, first, may hold a quoted comma: the other fields are read from the end.
        let header = try #require(history.csv.split(separator: "\r\n").first?.split(separator: ","))
        let lines = history.csv.split(separator: "\r\n").map {
            Array($0.split(separator: ",", omittingEmptySubsequences: false).suffix(header.count))
        }
        let unit = try #require(header.firstIndex(of: "unita"))
        let spesa = try #require(header.firstIndex(of: "spesa_usd"))
        let listino = try #require(header.firstIndex(of: "valore_listino_usd"))
        var sums: [Int: Decimal] = [spesa: 0, listino: 0]
        for line in lines.dropFirst() {
            #expect(line[spesa].isEmpty || line[unit] == "spesa")
            #expect(line[listino].isEmpty || line[unit] == "valoreListino")
            for column in [spesa, listino] where !line[column].isEmpty {
                sums[column, default: 0] += try #require(Decimal(string: String(line[column])))
            }
        }
        #expect(sums[spesa] == history.totals[.spesa]?.value)
        #expect(sums[listino] == history.totals[.valoreListino]?.value)
    }

    @Test func theDomandeAreOneGroupApartFromTheProgetti() {
        let groups = Set(Self.history(Self.mixedLedger(), .project).rows.map(\.group))
        #expect(groups == ["bubo", String(localized: "Domande")])
    }

    @Test func groupedByModelEachModelGetsItsShare() {
        let rows = Self.history(Self.mixedLedger(), .model).rows
        #expect(rows.first { $0.group == "claude-opus-4-1" }?.amount.value == 0.5)
        #expect(rows.first { $0.group == "claude-haiku-4-5" }?.amount.value == 0.25)
    }

    @Test func everyRowSaysItsOriginAndAnUnpricedModelIsNotIncomplete() throws {
        let rows = Self.history(Self.mixedLedger(), .provider).rows
        #expect(rows.first { $0.group == "OpenRouter" }?.origin == .reported)
        #expect(rows.first { $0.group == "Ollama" }?.unit == .gratis)
        let unpriced = try #require(rows.first { $0.group == "Custom" })
        #expect(unpriced.origin == .unpriced)
        #expect(!unpriced.amount.isIncomplete)
        #expect(Self.history(Self.mixedLedger(), .provider).totals[.spesa]?.isIncomplete == false)
        #expect(Self.history(Self.mixedLedger(), .provider).csv.contains("Custom,spesa,unpriced,,,"))
    }

    @Test func thePeriodLeavesOutOlderTurns() {
        let history = Self.history(Self.mixedLedger(), .project, period: .week)
        #expect(history.totals[.valoreListino]?.value == 1.25)
    }

    @Test func aGroupWithACommaIsQuotedInTheCSV() {
        let ledger = CostLedger()
        ledger.record(Self.usage(.apiKey, 0.1), turn: "t1", session: UUID(), project: URL(filePath: "/tmp/a, \"b\""),
                      at: Self.now)
        #expect(Self.history(ledger, .project).csv.contains(#""a, ""b""",spesa"#))
    }

    @Test func twelveMonthsOfTurnsAreGroupedWellUnderHalfASecond() {
        let sessions = (0..<40).map { _ in UUID() }
        let project = URL(filePath: "/tmp/bubo")
        let entries = (0..<(365 * 40)).map { index in
            CostLedger.Entry(id: "t\(index)", session: sessions[index % 40], project: project, provider: "Anthropic",
                             date: Self.now.addingTimeInterval(-Double(index) * 2_160),
                             usage: Self.usage(index.isMultiple(of: 3) ? .subscription : .apiKey, 0.01))
        }
        let elapsed = ContinuousClock().measure {
            _ = CostHistory(entries: entries, grouping: .session, period: .year, now: Self.now, calendar: Self.calendar)
        }
        #expect(elapsed < .milliseconds(500))
    }
}
