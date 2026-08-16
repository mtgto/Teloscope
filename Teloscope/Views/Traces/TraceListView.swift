// SPDX-License-Identifier: MIT
import SwiftUI
import SwiftData

private struct SessionTreeNode: Identifiable {
    enum Content {
        case session(SessionRow)
        case trace(TraceRow)
    }
    let id: String
    let content: Content
    let children: [SessionTreeNode]?
}

struct TraceListView: View {
    private let detailPanelMinHeight: CGFloat = 300

    @Environment(\.modelContext) private var modelContext
    @State private var model = TracesListModel()
    @State private var selection: TraceSelection?

    var body: some View {
        VSplitView {
            sessionList
                .frame(minHeight: 150)
            switch selection {
            case .session:
                if model.isLoadingSelection {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, minHeight: detailPanelMinHeight)
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            SessionSummaryView(spans: model.selectedSpans)
                                .background(.background)
                            Divider()
                            GanttChartView(spans: model.selectedSpans)
                        }
                    }
                    .frame(minHeight: detailPanelMinHeight)
                }
            case .trace:
                if model.isLoadingSelection {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, minHeight: detailPanelMinHeight)
                } else {
                    ScrollView(.vertical) {
                        GanttChartView(spans: model.selectedSpans)
                    }
                    .frame(minHeight: detailPanelMinHeight)
                }
            case nil:
                ContentUnavailableView(
                    "Select a Trace",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Select a trace from the list above to see the Gantt chart")
                )
                .frame(maxWidth: .infinity, minHeight: detailPanelMinHeight)
            }
        }
        .navigationTitle("Traces")
        .onAppear { model.reloadSessions(container: modelContext.container) }
        .onChange(of: selection) { _, newSelection in
            model.loadSelection(newSelection, container: modelContext.container)
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .otlpSpansIngested) {
                model.reloadSessions(container: modelContext.container)
            }
        }
    }

    private var sessionTreeNodes: [SessionTreeNode] {
        model.sessions.map { session in
            SessionTreeNode(
                id: "session-\(session.id)",
                content: .session(session),
                children: session.traces.map { trace in
                    SessionTreeNode(id: "trace-\(trace.traceId)", content: .trace(trace), children: nil)
                }
            )
        }
    }

    private var sessionList: some View {
        List(selection: $selection) {
            OutlineGroup(sessionTreeNodes, children: \.children) { node in
                switch node.content {
                case .session(let session):
                    sessionHeader(session)
                        .tag(TraceSelection.session(session.id))
                case .trace(let trace):
                    traceRow(trace)
                        .tag(TraceSelection.trace(trace.traceId))
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func sessionHeader(_ session: SessionRow) -> some View {
        HStack {
            Text(session.id == SessionRow.unknownSessionId ? "Unknown Session" : session.id)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
            Spacer()
            Text("\(session.traceCount) traces")
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
            Text(trace.traceId)
                .font(.system(.body, design: .monospaced))
            Spacer()
            Text(trace.rootSpanName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(trace.startTime.formatted(.dateTime.hour().minute().second().secondFraction(.milliseconds(3))))
                .foregroundStyle(.secondary)
                .font(.caption)
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
