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
            if !redactionReasons.contains(.placeholder) && slices.isEmpty {
                Text("No data")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    // Charts は .redacted に対応していないため、.placeholder 時のみ Circle で代替
                    // .invalidated 時は実チャートをそのまま表示（親の redaction でぼかされる）
                    if redactionReasons.contains(.placeholder) {
                        Circle()
                            .fill(.gray.opacity(0.3))
                            .frame(width: 80, height: 80)
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
                    Spacer()
                }
            }
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

#Preview("Loading") {
    PieWidgetView(
        title: "Approval Rate",
        slices: [
            PieSlice(label: "Approved (\(0))", value: 1, color: .green),
            PieSlice(label: "Rejected (\(0))", value: 1, color: .red),
        ],
        centerLabel: nil
    )
    .redacted(reason: .placeholder)
    .frame(width: 260)
    .padding()
}
