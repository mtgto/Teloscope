// SPDX-License-Identifier: MIT
import SwiftUI
import Charts

struct PieSlice: Identifiable {
    let id = UUID()
    let label: LocalizedStringKey
    let value: Double
    let color: Color
}

struct PieWidgetView: View {
    let title: LocalizedStringKey
    let slices: [PieSlice]
    /// Short text rendered in the donut hole (e.g. "78%"). Pass nil to omit.
    let centerLabel: String?

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 12) {
                Spacer()
                // Charts does not support .redacted, so use a plain Circle for .placeholder.
                // For .invalidated, the real chart is shown and blurred by the parent redaction.
                if redactionReasons.contains(.placeholder) || slices.isEmpty {
                    ZStack {
                        Circle()
                            .fill(.gray.opacity(0.15))
                            .frame(width: 80, height: 80)
                        Circle()
                            .fill(Color(NSColor.windowBackgroundColor))
                            .frame(width: 44, height: 44)
                    }
                } else {
                    ZStack {
                        Chart(slices) { slice in
                            SectorMark(
                                angle: .value("Value", slice.value),
                                innerRadius: .ratio(0.55),
                                angularInset: 1.5
                            )
                            .foregroundStyle(slice.color)
                        }
                        if let label = centerLabel {
                            Text(label)
                                .font(.caption2.bold())
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(width: 80, height: 80)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if slices.isEmpty {
                        ForEach(0..<2, id: \.self) { _ in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.gray)
                                    .frame(width: 8, height: 8)
                                Text("Placeholder")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .redacted(reason: .placeholder)
                    } else {
                        ForEach(slices, id: \.id) { slice in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(slice.color)
                                    .frame(width: 8, height: 8)
                                Text(slice.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(8)
        } label: {
            Text(title).unredacted()
        }
    }
}

#Preview {
    PieWidgetView(
        title: "Approval Rate",
        slices: [
            PieSlice(label: "Approved (\(35))", value: 35, color: .green),
            PieSlice(label: "Rejected (\(10))", value: 10, color: .red),
        ],
        centerLabel: "78%"
    )
    .frame(width: 260)
    .padding()
}

#Preview("No Data") {
    PieWidgetView(
        title: "Approval Rate",
        slices: [],
        centerLabel: nil
    )
    .frame(width: 260)
    .padding()
}

#Preview("Loading") {
    PieWidgetView(
        title: "Approval Rate",
        slices: [],
        centerLabel: nil
    )
    .redacted(reason: .placeholder)
    .frame(width: 260)
    .padding()
}
