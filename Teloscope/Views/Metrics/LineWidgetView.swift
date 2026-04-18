// SPDX-License-Identifier: MIT
import SwiftUI
import Charts

struct LineSeries: Identifiable {
    let id = UUID()
    let label: String
    let color: Color
    let dataPoints: [(date: Date, value: Double)]
}

struct LineWidgetView: View {
    let title: LocalizedStringKey
    let series: [LineSeries]
    let yAxisLabel: String
    let granularity: TimeGranularity

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        GroupBox {
            if redactionReasons.contains(.placeholder) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.gray.opacity(0.3))
                    .frame(height: 100)
            } else if series.allSatisfy({ $0.dataPoints.isEmpty }) {
                Text("No data")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Chart {
                        ForEach(series) { s in
                            ForEach(s.dataPoints, id: \.date) { point in
                                LineMark(
                                    x: .value("Time", point.date),
                                    y: .value("Value", point.value)
                                )
                                .foregroundStyle(by: .value("Series", s.label))
                                .interpolationMethod(.catmullRom)
                                PointMark(
                                    x: .value("Time", point.date),
                                    y: .value("Value", point.value)
                                )
                                .foregroundStyle(by: .value("Series", s.label))
                                .symbolSize(20)
                            }
                        }
                    }
                    .chartForegroundStyleScale(
                        domain: series.map(\.label),
                        range: series.map(\.color)
                    )
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisValueLabel(format: xAxisFormat)
                            AxisGridLine()
                        }
                    }
                    .chartYAxisLabel(yAxisLabel, position: .leading)
                    .chartLegend(.hidden)
                    .frame(height: 100)

                    if series.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(series) { s in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(s.color)
                                        .frame(width: 8, height: 8)
                                    Text(LocalizedStringKey(s.label))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
        } label: {
            Text(title).unredacted()
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch granularity {
        case .hourly: .dateTime.hour()
        case .daily, .weekly: .dateTime.month().day()
        }
    }
}

// MARK: - Previews

private let sampleDates: [Date] = (0..<24).map {
    Calendar.current.date(byAdding: .hour, value: $0, to: Calendar.current.startOfDay(for: .now))!
}

#Preview {
    LineWidgetView(
        title: "Tokens Over Time",
        series: [
            LineSeries(
                label: "Input Tokens",
                color: .blue,
                dataPoints: sampleDates.enumerated().map { i, d in (date: d, value: Double(i * 1200 + 800)) }
            ),
            LineSeries(
                label: "Output Tokens",
                color: .green,
                dataPoints: sampleDates.enumerated().map { i, d in (date: d, value: Double(i * 400 + 200)) }
            ),
        ],
        yAxisLabel: "tokens",
        granularity: .hourly
    )
    .frame(width: 300)
    .padding()
}

#Preview("Single series") {
    LineWidgetView(
        title: "Cost Over Time",
        series: [
            LineSeries(
                label: "Cost",
                color: .orange,
                dataPoints: sampleDates.enumerated().map { i, d in (date: d, value: Double(i) * 0.012) }
            ),
        ],
        yAxisLabel: "USD",
        granularity: .hourly
    )
    .frame(width: 300)
    .padding()
}

#Preview("Loading") {
    LineWidgetView(
        title: "Tokens Over Time",
        series: [],
        yAxisLabel: "tokens",
        granularity: .hourly
    )
    .redacted(reason: .placeholder)
    .frame(width: 300)
    .padding()
}
