import Foundation
import Testing
@testable import Bubo

/// The next time of each Ripetizione, in local time, across summer time and time zones.
struct RecurrenceTests {
    nonisolated struct Case: CustomTestStringConvertible, Sendable {
        let recurrence: Recurrence
        /// The instant the next time is asked after, ISO 8601 with its offset.
        let after: String
        /// The next time expected, ISO 8601 with its offset; `nil` for none.
        let expected: String?
        let zone: String
        let label: String

        init(_ label: String, _ recurrence: Recurrence, after: String, expected: String?, zone: String = "Europe/Rome") {
            self.label = label
            self.recurrence = recurrence
            self.after = after
            self.expected = expected
            self.zone = zone
        }

        var testDescription: String { label }
    }

    nonisolated static let cases: [Case] = [
        Case("ogni giorno, domani", .daily(hour: 9, minute: 0),
             after: "2026-10-01T10:00:00+02:00", expected: "2026-10-02T09:00:00+02:00"),
        Case("ogni giorno, oggi più tardi", .daily(hour: 9, minute: 0),
             after: "2026-10-02T08:59:00+02:00", expected: "2026-10-02T09:00:00+02:00"),
        Case("ogni giorno, mai nello stesso istante", .daily(hour: 9, minute: 0),
             after: "2026-10-02T09:00:00+02:00", expected: "2026-10-03T09:00:00+02:00"),
        Case("ogni giorno, il giorno dell'ora legale", .daily(hour: 9, minute: 0),
             after: "2026-03-28T10:00:00+01:00", expected: "2026-03-29T09:00:00+02:00"),
        Case("ogni giorno, ora saltata dall'ora legale", .daily(hour: 2, minute: 30),
             after: "2026-03-28T10:00:00+01:00", expected: "2026-03-29T03:00:00+02:00"),
        Case("ogni giorno, ora ripetuta dall'ora solare: la prima", .daily(hour: 2, minute: 30),
             after: "2026-10-24T10:00:00+02:00", expected: "2026-10-25T02:30:00+02:00"),
        Case("ogni giorno, ora ripetuta dall'ora solare: non la seconda", .daily(hour: 2, minute: 30),
             after: "2026-10-25T02:30:00+02:00", expected: "2026-10-26T02:30:00+01:00"),
        Case("ogni giorno, il giorno dell'ora solare", .daily(hour: 9, minute: 0),
             after: "2026-10-24T10:00:00+02:00", expected: "2026-10-25T09:00:00+01:00"),
        Case("ogni giorno, altro fuso", .daily(hour: 9, minute: 0),
             after: "2026-10-02T10:00:00+02:00", expected: "2026-10-02T09:00:00-04:00", zone: "America/New_York"),
        Case("ogni giorno, fuso a mezz'ora", .daily(hour: 9, minute: 0),
             after: "2026-10-02T10:00:00+05:30", expected: "2026-10-03T09:00:00+05:30", zone: "Asia/Kolkata"),
        Case("ogni ora", .hourly(minute: 15),
             after: "2026-10-02T10:20:00+02:00", expected: "2026-10-02T11:15:00+02:00"),
        Case("ogni ora, nella stessa ora", .hourly(minute: 15),
             after: "2026-10-02T10:05:00+02:00", expected: "2026-10-02T10:15:00+02:00"),
        Case("ogni ora, mai nello stesso istante", .hourly(minute: 0),
             after: "2026-10-02T10:00:00+02:00", expected: "2026-10-02T11:00:00+02:00"),
        Case("ogni ora, anche l'ora ripetuta", .hourly(minute: 30),
             after: "2026-10-25T02:45:00+02:00", expected: "2026-10-25T02:30:00+01:00"),
        Case("ogni ora, attraverso l'ora legale", .hourly(minute: 30),
             after: "2026-03-29T01:45:00+01:00", expected: "2026-03-29T03:30:00+02:00"),
        Case("ogni ora, fuso a mezz'ora", .hourly(minute: 0),
             after: "2026-10-02T10:20:00+05:30", expected: "2026-10-02T11:00:00+05:30", zone: "Asia/Kolkata"),
        Case("giorni feriali, venerdì più tardi", .weekdays(hour: 9, minute: 0),
             after: "2026-10-02T08:00:00+02:00", expected: "2026-10-02T09:00:00+02:00"),
        Case("giorni feriali, dopo il fine settimana", .weekdays(hour: 9, minute: 0),
             after: "2026-10-02T10:00:00+02:00", expected: "2026-10-05T09:00:00+02:00"),
        Case("giorni feriali, di sabato", .weekdays(hour: 9, minute: 0),
             after: "2026-10-03T08:00:00+02:00", expected: "2026-10-05T09:00:00+02:00"),
        Case("giorni feriali, dopo l'ora solare", .weekdays(hour: 9, minute: 0),
             after: "2026-10-23T10:00:00+02:00", expected: "2026-10-26T09:00:00+01:00"),
        Case("un giorno della settimana, lunedì", .weekly(weekday: 2, hour: 9, minute: 0),
             after: "2026-10-02T10:00:00+02:00", expected: "2026-10-05T09:00:00+02:00"),
        Case("un giorno della settimana, la settimana dopo", .weekly(weekday: 2, hour: 9, minute: 0),
             after: "2026-10-05T09:00:00+02:00", expected: "2026-10-12T09:00:00+02:00"),
        Case("un giorno della settimana, domenica dell'ora solare", .weekly(weekday: 1, hour: 9, minute: 0),
             after: "2026-10-24T10:00:00+02:00", expected: "2026-10-25T09:00:00+01:00"),
        Case("una volta, nel futuro", .once(try! Date("2026-10-03T09:00:00+02:00", strategy: .iso8601)),
             after: "2026-10-02T10:00:00+02:00", expected: "2026-10-03T09:00:00+02:00"),
        Case("una volta, passata", .once(try! Date("2026-10-01T09:00:00+02:00", strategy: .iso8601)),
             after: "2026-10-02T10:00:00+02:00", expected: nil),
    ]

    @Test(arguments: cases)
    func theNextTimeIsTheOneExpected(_ example: Case) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: example.zone))
        let after = try Date(example.after, strategy: .iso8601)
        let expected = try example.expected.map { try Date($0, strategy: .iso8601) }

        #expect(example.recurrence.nextDate(after: after, in: calendar) == expected)
    }

    @Test func aPausedAutomationHasNoNextTime() {
        var automation = Automation(id: UUID(), name: "Controllo", project: URL(filePath: "/tmp"), request: "Controlla",
                                    recurrence: .hourly(minute: 0))
        #expect(automation.nextDate(after: .now) != nil)
        automation.isPaused = true
        #expect(automation.nextDate(after: .now) == nil)
    }

    @Test func anAutomationSavedBeforeTheRepetitionsKeepsItsOnlyExecution() throws {
        let session = UUID()
        let json = """
            {"id":"\(UUID().uuidString)","name":"Vecchia","project":"file:///tmp/","request":"Fai",
             "model":{"router":{}},"isAutonomous":true,"rules":["Bash(ls)"],
             "lastExecution":{"startedAt":0,"session":"\(session.uuidString)","outcome":"fatta","denialCount":1}}
            """
        let automation = try JSONDecoder().decode(Automation.self, from: Data(json.utf8))

        #expect(automation.recurrence == nil)
        #expect(!automation.isPaused)
        #expect(automation.rules == ["Bash(ls)"])
        #expect(automation.executions.map(\.session) == [session])
        #expect(automation.lastExecution?.outcome == .fatta)
    }

    @Test func theMissedTimesAreTheOnesBetweenTwoInstantsOldestFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        let start = try Date("2026-10-23T09:00:00+02:00", strategy: .iso8601)
        let end = try Date("2026-10-26T09:00:00+01:00", strategy: .iso8601)

        let dates = Recurrence.daily(hour: 9, minute: 0).dates(after: start, through: end, in: calendar)

        #expect(dates == [try Date("2026-10-24T09:00:00+02:00", strategy: .iso8601),
                          try Date("2026-10-25T09:00:00+01:00", strategy: .iso8601),
                          end])
        #expect(Recurrence.once(start).dates(after: start, through: end, in: calendar).isEmpty)
    }
}
