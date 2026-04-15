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

struct SessionRow: Identifiable {
    let id: String          // session.id value, or "unknown"
    let traces: [TraceRow]  // sorted newest-first

    var startTime: Date { traces.first?.startTime ?? .distantPast }
    var traceCount: Int { traces.count }
}

enum TraceSelection: Hashable {
    case session(String)
    case trace(String)
}

struct TraceListView: View {
    @Query(sort: \OTLPSpan.startTime, order: .reverse) private var allSpans: [OTLPSpan]
    @State private var selection: TraceSelection?
    @State private var expandedSessions: Set<String> = []

    private var sessions: [SessionRow] {
        let byTrace = Dictionary(grouping: allSpans, by: \.traceId)

        let traceRows: [TraceRow] = byTrace.map { traceId, spans in
            let rootSpan = spans.first { $0.parentSpanId == nil } ?? spans[0]
            return TraceRow(
                id: traceId,
                traceId: traceId,
                startTime: rootSpan.startTime,
                spanCount: spans.count,
                rootSpanName: rootSpan.name
            )
        }

        let traceSessionMap: [String: String] = byTrace.reduce(into: [:]) { dict, kv in
            dict[kv.key] = sessionId(for: kv.value)
        }

        let bySession = Dictionary(grouping: traceRows) { traceSessionMap[$0.traceId] ?? "unknown" }

        return bySession.map { sid, rows in
            SessionRow(id: sid, traces: rows.sorted { $0.startTime > $1.startTime })
        }
        .sorted { $0.startTime > $1.startTime }
    }

    private var selectedSpans: [OTLPSpan] {
        switch selection {
        case .session(let sid):
            let traceIds = Set(sessions.first { $0.id == sid }?.traces.map(\.traceId) ?? [])
            return allSpans.filter { traceIds.contains($0.traceId) }
                .sorted { $0.startTime < $1.startTime }
        case .trace(let traceId):
            return allSpans.filter { $0.traceId == traceId }
                .sorted { $0.startTime < $1.startTime }
        case nil:
            return []
        }
    }

    private func sessionId(for spans: [OTLPSpan]) -> String {
        let preferred = spans.first { $0.parentSpanId == nil } ?? spans[0]
        for span in ([preferred] + spans) {
            if let attr = span.attributes.first(where: { $0.key == "session.id" }),
               case .string(let value) = attr.value {
                return value
            }
        }
        return "unknown"
    }

    var body: some View {
        VSplitView {
            sessionList
                .frame(minHeight: 150)
            switch selection {
            case .session:
                VStack(spacing: 0) {
                    SessionSummaryView(spans: selectedSpans)
                        .background(.background)
                    Divider()
                    GanttChartView(spans: selectedSpans)
                }
                .frame(minHeight: 200)
            case .trace:
                GanttChartView(spans: selectedSpans)
                    .frame(minHeight: 200)
            case nil:
                ContentUnavailableView(
                    "Select a Trace",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Select a trace from the list above to see the Gantt chart")
                )
            }
        }
        .navigationTitle("Traces")
    }

    private var sessionList: some View {
        List(selection: $selection) {
            ForEach(sessions) { session in
                let isExpanded = Binding(
                    get: { expandedSessions.contains(session.id) },
                    set: { if $0 { expandedSessions.insert(session.id) } else { expandedSessions.remove(session.id) } }
                )
                DisclosureGroup(isExpanded: isExpanded) {
                    ForEach(session.traces) { trace in
                        traceRow(trace).tag(TraceSelection.trace(trace.traceId))
                    }
                } label: {
                    sessionHeader(session)
                }
                .tag(TraceSelection.session(session.id))
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func sessionHeader(_ session: SessionRow) -> some View {
        HStack {
            Text(session.id == "unknown" ? "Unknown Session" : String(session.id.prefix(16)))
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
            Spacer()
            Text("\(session.traceCount) trace\(session.traceCount == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(session.startTime.formatted(.dateTime.month().day().hour().minute()))
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func traceRow(_ trace: TraceRow) -> some View {
        HStack {
            Text(String(trace.traceId.prefix(16)))
                .font(.system(.body, design: .monospaced))
            Spacer()
            Text(trace.rootSpanName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(trace.startTime.formatted(.dateTime.hour().minute().second().secondFraction(.milliseconds(3))))
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("\(trace.spanCount)")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(minWidth: 20, alignment: .trailing)
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
