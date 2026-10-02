import RemoteKit
import SwiftUI

/// The Battito of a Mac: when it was last seen, and a warning without color once the data may be old (spec 21).
struct HeartbeatRow: View {
    let macName: String
    /// The latest Battito; `nil` before the first.
    let heartbeat: Heartbeat?

    var body: some View {
        if let heartbeat {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                row(heartbeat, at: context.date)
            }
        } else {
            VStack(alignment: .leading) {
                Text(verbatim: macName)
                Text("Ancora nessun Battito")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func row(_ heartbeat: Heartbeat, at date: Date) -> some View {
        let isStale = heartbeat.isStale(at: date)
        let age = heartbeat.sentAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return HStack(alignment: .firstTextBaseline) {
            if isStale {
                Image(systemName: heartbeat.isAsleep ? "moon.zzz" : "clock")
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading) {
                Text(verbatim: macName)
                Group {
                    if heartbeat.isAsleep {
                        Text("Il Mac dorme, visto \(age): i dati possono essere vecchi")
                    } else if isStale {
                        Text("Visto \(age): i dati possono essere vecchi")
                    } else {
                        Text("Visto \(age)")
                    }
                }
                .font(.footnote)
                .foregroundStyle(isStale ? .primary : .secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: macName))
        .accessibilityValue(isStale ? Text("Dati di \(age), possono essere vecchi") : Text("Visto \(age)"))
    }
}
