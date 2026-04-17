// SPDX-License-Identifier: MIT
import SwiftUI

struct StatWidgetView: View {
    let title: String
    let primaryValue: String
    let rows: [(label: String, value: String)]

    var body: some View {
        GroupBox(LocalizedStringKey(title)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(primaryValue)
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !rows.isEmpty {
                    Divider()
                    ForEach(rows, id: \.label) { row in
                        HStack {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Spacer()
                            Text(row.value)
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity)
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
