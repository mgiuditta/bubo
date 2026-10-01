import AppKit
import SwiftUI

/// Impostazioni › Diagnostica: the latest MetricKit day, kept on this Mac and never sent.
struct DiagnosticsView: View {
    /// The reports on disk; `nil` until they are read.
    @State private var reports: SavedReports?
    private let store = try? DiagnosticsStore.makeDefault()

    var body: some View {
        Form {
            Section {
                if let reports {
                    if let day = reports.latestDay {
                        DailyMetricsRows(day: day)
                    } else {
                        Text("Nessun report ancora")
                        Text("macOS li consegna al massimo una volta al giorno, e a volte per niente.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LoadingLabel("Leggo i report…")
                }
            } header: {
                if let day = reports?.latestDay {
                    Text("Ultimo giorno: \(day.end, format: .dateTime.day().month(.wide).year())")
                } else {
                    Text("Ultimo giorno")
                }
            } footer: {
                Text("I report restano su questo Mac per 30 giorni: Bubo non li invia a nessuno.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Mostra nel Finder", action: showInFinder)
                .disabled(reports?.isEmpty ?? true)
        }
        .formStyle(.grouped)
        .task { reports = await Self.read(store) }
    }

    private func showInFinder() {
        guard let store else { return }
        NSWorkspace.shared.activateFileViewerSelecting([store.folder])
    }

    @concurrent
    private static func read(_ store: DiagnosticsStore?) async -> SavedReports {
        SavedReports(latestDay: store?.latestDay(), isEmpty: !(store?.hasReports ?? false))
    }
}

/// What the Diagnostica section knows of the reports on disk.
private struct SavedReports {
    /// The summary of the latest day; `nil` when no metric payload arrived.
    var latestDay: DailyMetrics?
    /// Whether the folder has no report at all, metric or diagnostic.
    var isEmpty: Bool
}

/// The rows of one MetricKit day: launch, hangs, peak memory, hitches.
private struct DailyMetricsRows: View {
    let day: DailyMetrics

    /// Seconds with two decimals, such as "0,42 s".
    private static let seconds = Duration.UnitsFormatStyle(allowedUnits: [.seconds], width: .abbreviated,
                                                           fractionalPart: .show(length: 2))

    var body: some View {
        LabeledContent("Avvio medio") {
            if let launch = day.meanLaunch {
                Text(launch, format: Self.seconds)
            } else {
                Text("Non misurato")
            }
        }
        LabeledContent("Blocchi dell'app") {
            if day.hangCount == 0 {
                Text("Nessuno")
            } else {
                Text("\(day.hangCount), \(day.hangTime, format: Self.seconds) in tutto")
            }
        }
        LabeledContent("Memoria di picco") {
            if let peak = day.peakMemory {
                Text(peak, format: .byteCount(style: .memory))
            } else {
                Text("Non misurata")
            }
        }
        LabeledContent("Scatti nelle animazioni") {
            if let ratio = day.hitchRatio {
                Text(ratio, format: .percent.precision(.fractionLength(0...2)))
            } else {
                Text("Non misurati")
            }
        }
    }
}
