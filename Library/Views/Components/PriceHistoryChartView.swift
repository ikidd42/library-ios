import SwiftUI
import Charts

/// Shows a line chart of eBay price history for a book
struct PriceHistoryChartView: View {
    let entries: [PriceHistoryEntry]

    private var sortedEntries: [PriceHistoryEntry] {
        entries.sorted { $0.fetchedAt < $1.fetchedAt }
    }

    private var minPrice: Double {
        entries.map(\.price).min() ?? 0
    }

    private var maxPrice: Double {
        entries.map(\.price).max() ?? 0
    }

    private var avgPrice: Double {
        guard !entries.isEmpty else { return 0 }
        return entries.map(\.price).reduce(0, +) / Double(entries.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sortedEntries.count >= 2 {
                chart
            } else if sortedEntries.count == 1 {
                singleDataPoint
            } else {
                Text("No price history yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if sortedEntries.count >= 2 {
                statsRow
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(sortedEntries, id: \.fetchedAt) { entry in
                LineMark(
                    x: .value("Date", entry.fetchedAt),
                    y: .value("Price", entry.price)
                )
                .foregroundStyle(.green)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", entry.fetchedAt),
                    y: .value("Price", entry.price)
                )
                .foregroundStyle(.green)
                .symbolSize(30)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(formatPrice(price))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 160)
    }

    private var singleDataPoint: some View {
        HStack {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.secondary)
            Text("First price recorded: \(formatPrice(sortedEntries[0].price))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("on \(sortedEntries[0].fetchedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            statPill(label: "Low", value: formatPrice(minPrice), color: .green)
            statPill(label: "Avg", value: formatPrice(avgPrice), color: .blue)
            statPill(label: "High", value: formatPrice(maxPrice), color: .orange)
            Spacer()
            Text("\(sortedEntries.count) checks")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private func formatPrice(_ price: Double) -> String {
        price.formattedAsPrice()
    }
}
