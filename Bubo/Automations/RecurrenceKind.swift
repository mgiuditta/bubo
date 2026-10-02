import Foundation

/// The five Ripetizioni as the Automazione sheet offers them, before their time is chosen.
enum RecurrenceKind: String, CaseIterable, Identifiable {
    case once, hourly, daily, weekdays, weekly

    var id: Self { self }

    /// Creates the kind of `recurrence`.
    init(_ recurrence: Recurrence) {
        self = switch recurrence {
        case .once: .once
        case .hourly: .hourly
        case .daily: .daily
        case .weekdays: .weekdays
        case .weekly: .weekly
        }
    }

    /// The name in the sheet's picker.
    var title: LocalizedStringResource {
        switch self {
        case .once: "Una volta"
        case .hourly: "Ogni ora"
        case .daily: "Ogni giorno"
        case .weekdays: "Giorni feriali"
        case .weekly: "Un giorno della settimana"
        }
    }

    /// The Ripetizione of this kind at the hour and minute of `time`, its day too for Una volta; `weekday` only for
    /// Un giorno della settimana.
    func recurrence(at time: Date, on weekday: Int, in calendar: Calendar = .autoupdatingCurrent) -> Recurrence {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let hour = parts.hour ?? 9
        let minute = parts.minute ?? 0
        return switch self {
        case .once: .once(calendar.dateInterval(of: .minute, for: time)?.start ?? time)
        case .hourly: .hourly(minute: minute)
        case .daily: .daily(hour: hour, minute: minute)
        case .weekdays: .weekdays(hour: hour, minute: minute)
        case .weekly: .weekly(weekday: weekday, hour: hour, minute: minute)
        }
    }

    /// The time the sheet shows for `recurrence`: today at its hour and minute, or its date for Una volta.
    static func time(of recurrence: Recurrence, in calendar: Calendar = .autoupdatingCurrent) -> Date {
        let hour: Int
        let minute: Int
        switch recurrence {
        case let .once(date): return date
        case let .hourly(due): (hour, minute) = (calendar.component(.hour, from: .now), due)
        case let .daily(due, at), let .weekdays(due, at), let .weekly(_, due, at): (hour, minute) = (due, at)
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
}
