import Foundation

/// When an Automazione runs by itself, in the Mac's local time: no cron expressions (spec 19).
nonisolated enum Recurrence: Codable, Hashable, Sendable {
    /// Once, at `date`.
    case once(Date)
    /// Every hour, at `minute` past it.
    case hourly(minute: Int)
    /// Every day at `hour`:`minute`.
    case daily(hour: Int, minute: Int)
    /// Monday to Friday at `hour`:`minute`.
    case weekdays(hour: Int, minute: Int)
    /// Every week on `weekday`, as `Calendar` counts them (1 is Sunday), at `hour`:`minute`.
    case weekly(weekday: Int, hour: Int, minute: Int)

    /// The first time strictly after `date` in the local time of `calendar`; `nil` once a single run is past.
    ///
    /// A time the change to summer time skips moves to the first one after it; one that the change back repeats
    /// happens the first time only. Every hour still fires each hour, the repeated one too.
    func nextDate(after date: Date, in calendar: Calendar) -> Date? {
        switch self {
        case let .once(due):
            return due > date ? due : nil
        case let .hourly(minute):
            guard let hour = calendar.dateInterval(of: .hour, for: date)?.start else { return nil }
            let due = hour.addingTimeInterval(TimeInterval(minute * 60))
            return due > date ? due : due.addingTimeInterval(60 * 60)
        case let .daily(hour, minute):
            return Self.next(DateComponents(hour: hour, minute: minute), after: date, in: calendar)
        case let .weekdays(hour, minute):
            var due = date
            // At most three days pass over a weekend.
            for _ in 0..<4 {
                guard let next = Self.next(DateComponents(hour: hour, minute: minute), after: due, in: calendar)
                else { return nil }
                if (2...6).contains(calendar.component(.weekday, from: next)) { return next }
                due = next
            }
            return nil
        case let .weekly(weekday, hour, minute):
            return Self.next(DateComponents(hour: hour, minute: minute, weekday: weekday), after: date, in: calendar)
        }
    }

    /// The times strictly after `start` and up to `end`, oldest first, in the local time of `calendar`.
    func dates(after start: Date, through end: Date, in calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        var date = start
        while let next = nextDate(after: date, in: calendar), next <= end {
            dates.append(next)
            date = next
        }
        return dates
    }

    private static func next(_ components: DateComponents, after date: Date, in calendar: Calendar) -> Date? {
        calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime, repeatedTimePolicy: .first,
                          direction: .forward)
    }
}

nonisolated extension Recurrence {
    /// How the Ripetizione reads in the Automazioni window, in `calendar`: "Ogni giorno alle 09:00".
    func title(in calendar: Calendar = .autoupdatingCurrent) -> String {
        switch self {
        case let .once(date):
            return String(localized: "Una volta, \(date.formatted(date: .abbreviated, time: .shortened))")
        case let .hourly(minute):
            return String(localized: "Ogni ora, al minuto \(minute)")
        case let .daily(hour, minute):
            return String(localized: "Ogni giorno alle \(Self.time(hour, minute, in: calendar))")
        case let .weekdays(hour, minute):
            return String(localized: "Giorni feriali alle \(Self.time(hour, minute, in: calendar))")
        case let .weekly(weekday, hour, minute):
            let day = calendar.weekdaySymbols[(weekday - 1 + 7) % 7]
            return String(localized: "Ogni \(day) alle \(Self.time(hour, minute, in: calendar))")
        }
    }

    /// `hour`:`minute` as the Mac shows times.
    private static func time(_ hour: Int, _ minute: Int, in calendar: Calendar) -> String {
        let date = calendar.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        return date.formatted(.dateTime.hour().minute())
    }
}
