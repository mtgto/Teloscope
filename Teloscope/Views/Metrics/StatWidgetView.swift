// SPDX-License-Identifier: MIT
import SwiftUI

struct StatWidgetView: View {
    let title: LocalizedStringKey
    let primaryValue: String
    let rows: [(label: LocalizedStringKey, value: String)]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                if rows.isEmpty {
                    Text(primaryValue)
                        .font(.title.monospacedDigit())
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    Text(primaryValue)
                        .font(.title2.monospacedDigit())
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    ForEach(rows.indices, id: \.self) { i in
                        HStack {
                            Text(rows[i].label)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Spacer()
                            Text(rows[i].value)
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(8)
        } label: {
            Text(title).unredacted()
        }
    }
}

#Preview {
    StatWidgetView(
        title: "Total Tokens",
        primaryValue: "1,234,567",
        rows: [
            (label: "Input", value: "800,000"),
            (label: "Output", value: "400,000"),
            (label: "Cache Read", value: "34,567"),
        ]
    )
    .frame(width: 220)
    .padding()
}

#Preview("Empty rows") {
    StatWidgetView(
        title: "Total Cost",
        primaryValue: "$12.34",
        rows: []
    )
    .frame(width: 220)
    .padding()
}

#Preview("Loading") {
    StatWidgetView(
        title: "Total Tokens",
        primaryValue: "000,000",
        rows: [
            (label: "Input", value: "000,000"),
            (label: "Output", value: "000,000"),
            (label: "Cache Read", value: "000,000"),
        ]
    )
    .redacted(reason: .placeholder)
    .frame(width: 220)
    .padding()
}
