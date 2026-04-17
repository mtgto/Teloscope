// SPDX-License-Identifier: MIT
import SwiftUI

struct SpanDetailView: View {
    let span: OTLPSpan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(span.name)
                .font(.headline)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                detailRow("Trace ID", span.traceId)
                detailRow("Span ID", span.spanId)
                if let parent = span.parentSpanId {
                    detailRow("Parent Span ID", parent)
                }
                detailRow("Kind", "\(span.kind)")
                detailRow("Status", "\(span.status)")
                detailRow("Duration", durationText)
            }
            if !span.attributes.isEmpty {
                Divider()
                Text("Attributes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                    ForEach(span.attributes, id: \.key) { attr in
                        GridRow {
                            Text(attr.key)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            Text(verbatim: attr.value.map { "\($0)" } ?? "")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: 400)
    }

    private func detailRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var durationText: String {
        let ms = span.endTime.timeIntervalSince(span.startTime) * 1000
        return String(format: "%.2f ms", ms)
    }
}
