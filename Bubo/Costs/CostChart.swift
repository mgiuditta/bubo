import Charts
import SwiftUI

/// The bars of one unit over time, a day or a month each; the table grouped by Periodo holds the same figures.
struct CostChart: View {
    let points: [CostHistory.Point]
    let unit: CostUnit
    let bucket: Calendar.Component

    var body: some View {
        Chart(points) { point in
            BarMark(x: .value("Data", point.date, unit: bucket),
                    y: .value(Text(unit.title), (point.value as NSDecimalNumber).doubleValue))
                .foregroundStyle(Palette.textPrimary.opacity(0.7))
                .accessibilityLabel(Text(point.date, format: dateFormat))
                .accessibilityValue(Text(point.value, format: .currency(code: "USD")))
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Palette.line)
                AxisValueLabel {
                    if let figure = value.as(Double.self) {
                        Text(figure, format: .currency(code: "USD").precision(.fractionLength(0...2)))
                    }
                }
            }
        }
        .accessibilityLabel(Text("Grafico di \(Text(unit.title)) nel tempo"))
        .accessibilityHint(Text("Le stesse cifre sono nella tabella, raggruppata per Periodo."))
    }

    private var dateFormat: Date.FormatStyle {
        bucket == .month ? .dateTime.month(.wide).year() : .dateTime.day().month(.abbreviated).year()
    }
}
