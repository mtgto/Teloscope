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
    @State private var cachedSessions: [SessionRow] = []
    @State private var selectedSpans: [OTLPSpan] = []
    @State private var isLoadingSelection = false
    @State private var selectionTask: Task<Void, Never>?

    var body: some View {
        VSplitView {
            sessionList
                .frame(minHeight: 150)
            switch selection {
            case .session:
                if isLoadingSelection {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    VStack(spacing: 0) {
                        SessionSummaryView(spans: selectedSpans)
                            .background(.background)
                        Divider()
                        GanttChartView(spans: selectedSpans)
                    }
                    .frame(minHeight: 200)
                }
            case .trace:
                if isLoadingSelection {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    GanttChartView(spans: selectedSpans)
                        .frame(minHeight: 200)
                }
            case nil:
                ContentUnavailableView(
                    "Select a Trace",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Select a trace from the list above to see the Gantt chart")
                )
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Traces")
        .onAppear { rebuildSessions() }
        .onChange(of: allSpans) { rebuildSessions() }
        .onChange(of: selection) { _, newSelection in
            updateSelectedSpans(for: newSelection)
        }
    }

    private func rebuildSessions() {
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

        cachedSessions = bySession.map { sid, rows in
            SessionRow(id: sid, traces: rows.sorted { $0.startTime > $1.startTime })
        }
        .sorted { $0.startTime > $1.startTime }
    }

    private func updateSelectedSpans(for newSelection: TraceSelection?) {
        selectionTask?.cancel()
        guard let newSelection else {
            selectedSpans = []
            isLoadingSelection = false
            return
        }
        isLoadingSelection = true
        selectionTask = Task { @MainActor in
            // Yield so SwiftUI can re-render the ProgressView before we start computing
            await Task.yield()
            guard !Task.isCancelled else { return }

            let spans: [OTLPSpan]
            switch newSelection {
            case .session(let sid):
                let traceIds = Set(cachedSessions.first { $0.id == sid }?.traces.map(\.traceId) ?? [])
                spans = allSpans.filter { traceIds.contains($0.traceId) }
                    .sorted { $0.startTime < $1.startTime }
            case .trace(let traceId):
                spans = allSpans.filter { $0.traceId == traceId }
                    .sorted { $0.startTime < $1.startTime }
            }

            guard !Task.isCancelled else { return }
            selectedSpans = spans
            isLoadingSelection = false
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

    private var sessionList: some View {
        List(selection: $selection) {
            ForEach(cachedSessions) { session in
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
