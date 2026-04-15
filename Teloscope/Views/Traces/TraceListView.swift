// SPDX-License-Identifier: MIT
import SwiftUI
import SwiftData

struct TraceRow: Identifiable {
    let id: String
    let traceId: String
    let startTime: Date
    let spanCount: Int
    let rootSpanName: String
}

struct TraceListView: View {
    @Query(sort: \OTLPSpan.startTime, order: .reverse) private var allSpans: [OTLPSpan]
    @State private var selectedTraceId: String?

    private var traces: [TraceRow] {
        let grouped = Dictionary(grouping: allSpans, by: \.traceId)
        return grouped.map { traceId, spans in
            let rootSpan = spans.first { $0.parentSpanId == nil } ?? spans[0]
            return TraceRow(
                id: traceId,
                traceId: traceId,
                startTime: rootSpan.startTime,
                spanCount: spans.count,
                rootSpanName: rootSpan.name
            )
        }
        .sorted { $0.startTime > $1.startTime }
    }

    private var selectedSpans: [OTLPSpan] {
        guard let traceId = selectedTraceId else { return [] }
        return allSpans.filter { $0.traceId == traceId }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VSplitView {
            traceTable
                .frame(minHeight: 150)
            if selectedTraceId != nil {
                GanttChartView(spans: selectedSpans)
                    .frame(minHeight: 200)
            } else {
                ContentUnavailableView(
                    "Select a Trace",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Select a trace from the list above to see the Gantt chart")
                )
            }
        }
        .navigationTitle("Traces")
    }

    private var traceTable: some View {
        Table(traces, selection: $selectedTraceId) {
            TableColumn("Trace ID") { row in
                Text(String(row.traceId.prefix(16)))
                    .font(.system(.body, design: .monospaced))
            }
            TableColumn("Root Span") { row in
                Text(row.rootSpanName)
            }
            TableColumn("Start Time") { row in
                Text(row.startTime.formatted(.dateTime.hour().minute().second().secondFraction(.milliseconds(3))))
            }
            TableColumn("Spans") { row in
                Text("\(row.spanCount)")
            }
        }
    }
}

#Preview {
    TraceListView()
        .modelContainer(
            for: [ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
                  ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self],
            inMemory: true
        )
}
