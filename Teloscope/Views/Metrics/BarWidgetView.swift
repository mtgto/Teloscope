// SPDX-License-Identifier: MIT
import SwiftUI
import Charts

struct BarWidgetView: View {
    let title: LocalizedStringKey
    /// Items sorted descending by count. Only the top 10 are displayed.
    let items: [(name: String, count: Int)]

    @Environment(\.redactionReasons) private var redactionReasons

    private var displayItems: [(name: String, count: Int)] { Array(items.prefix(10)) }

    var body: some View {
        GroupBox {
            if redactionReasons.contains(.placeholder) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.gray.opacity(0.3))
                    .frame(height: 100)
            } else if items.isEmpty {
                Text("No data")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                Chart {
                    ForEach(displayItems, id: \.name) { item in
                        BarMark(
                            x: .value("Count", item.count),
                            y: .value("Tool", item.name)
                        )
                        .foregroundStyle(Color.accentColor)
                        .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                            Text("\(item.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in AxisValueLabel() }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(displayItems.count) * 22 + 8)
                .padding(8)
            }
        } label: {
            Text(title).unredacted()
        }
    }
}

// MARK: - Previews

#Preview {
    BarWidgetView(
        title: "Tool Usage",
        items: [
            (name: "bash",   count: 42),
            (name: "read",   count: 38),
            (name: "write",  count: 21),
            (name: "edit",   count: 17),
            (name: "grep",   count: 9),
        ]
    )
    .frame(width: 220)
    .padding()
}

#Preview("Empty") {
    BarWidgetView(title: "Tool Usage", items: [])
        .frame(width: 220)
        .padding()
}

#Preview("Loading") {
    BarWidgetView(title: "Tool Usage", items: [])
        .redacted(reason: .placeholder)
        .frame(width: 220)
        .padding()
}
