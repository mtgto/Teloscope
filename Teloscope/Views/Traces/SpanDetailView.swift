// SPDX-License-Identifier: MIT
import SwiftUI
import SwiftData

struct SpanDetailView: View {
    let span: TraceSpanSnapshot

    @Environment(\.modelContext) private var modelContext
    @State private var attributes: [(key: String, value: String)] = []

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
            if !attributes.isEmpty {
                Divider()
                Text("Attributes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                    ForEach(attributes, id: \.key) { attr in
                        GridRow {
                            Text(attr.key)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            Text(verbatim: attr.value)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: 400)
        .task(id: span.spanId) { loadAttributes() }
    }

    // Attributes are not carried in the snapshot — faulting them for a whole session
    // was an N+1 query storm. Only this popover needs them, for one span at a time.
    private func loadAttributes() {
        guard let persistentID = span.persistentID,
              let model = modelContext.model(for: persistentID) as? OTLPSpan else {
            attributes = []
            return
        }
        attributes = model.attributes.map { (key: $0.key, value: $0.value.map { "\($0)" } ?? "") }
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
