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
    let xDomain: ClosedRange<Date>

    @Environment(\.redactionReasons) private var redactionReasons
    @State private var selectedDate: Date?

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
                        if let selectedDate {
                            RuleMark(x: .value("Selected", selectedDate))
                                .foregroundStyle(.secondary.opacity(0.4))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                .annotation(
                                    position: .automatic,
                                    spacing: 4,
                                    overflowResolution: .init(x: .automatic, y: .fit(to: .chart))
                                ) {
                                    tooltipView(for: selectedDate)
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
                    .chartXScale(domain: xDomain)
                    .chartYAxisLabel(yAxisLabel, position: .leading)
                    .chartLegend(.hidden)
                    .chartXSelection(value: $selectedDate)
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

    private func tooltipView(for date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date, format: xAxisFormat)
                .font(.caption2.bold())
                .foregroundStyle(.primary)
            ForEach(series) { s in
                if let point = nearestPoint(in: s.dataPoints, to: date) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(s.color)
                            .frame(width: 6, height: 6)
                        Text(formattedValue(point.value))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func nearestPoint(
        in dataPoints: [(date: Date, value: Double)],
        to date: Date
    ) -> (date: Date, value: Double)? {
        dataPoints.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    private func formattedValue(_ value: Double) -> String {
        if yAxisLabel == "USD" {
            return value.formatted(.currency(code: "USD"))
        }
        return value.formatted(.number.precision(.fractionLength(0)))
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
        granularity: .hourly,
        xDomain: sampleDates.first!...sampleDates.last!
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
        granularity: .hourly,
        xDomain: sampleDates.first!...sampleDates.last!
    )
    .frame(width: 300)
    .padding()
}

// Hours 0-3 missing (start gap), 10-13 missing (middle gap), 20-23 missing (end gap)
private let gappedDates: [(date: Date, value: Double)] = sampleDates.enumerated().compactMap { i, d in
    guard !(0...3).contains(i), !(10...13).contains(i), !(20...23).contains(i) else { return nil }
    return (date: d, value: Double(i * 1200 + 800))
}

#Preview("With gaps") {
    LineWidgetView(
        title: "Tokens Over Time",
        series: [
            LineSeries(label: "Input Tokens", color: .blue, dataPoints: gappedDates),
        ],
        yAxisLabel: "tokens",
        granularity: .hourly,
        xDomain: sampleDates.first!...sampleDates.last!
    )
    .frame(width: 300)
    .padding()
}

#Preview("Loading") {
    LineWidgetView(
        title: "Tokens Over Time",
        series: [],
        yAxisLabel: "tokens",
        granularity: .hourly,
        xDomain: sampleDates.first!...sampleDates.last!
    )
    .redacted(reason: .placeholder)
    .frame(width: 300)
    .padding()
}
