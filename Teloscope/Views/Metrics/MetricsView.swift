// SPDX-License-Identifier: MIT
import SwiftUI
import SwiftData

struct MetricsView: View {
    @Query(sort: \OTLPSpan.startTime, order: .reverse) private var allSpans: [OTLPSpan]
    @State private var dashboardModel = MetricsDashboardModel()
    @State private var dateRange: DateInterval = MetricsDashboardModel.defaultDateRange()
    @State private var selectedModels: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                availableModels: dashboardModel.availableModels,
                dateRange: $dateRange,
                selectedModels: $selectedModels
            )
            .background(.bar)
            Divider()
            Group {
                if dashboardModel.isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let m = dashboardModel.metrics, m.sessionCount > 0 || m.totalInputTokens > 0 {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            costWidget(m).frame(maxHeight: .infinity)
                            tokensWidget(m).frame(maxHeight: .infinity)
                            sessionsWidget(m).frame(maxHeight: .infinity)
                            approvalWidget(m).frame(maxHeight: .infinity)
                            modelWidget(m).frame(maxHeight: .infinity)
                        }
                        .padding(12)
                    }
                } else {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("No spans recorded in the selected range.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Metrics")
        .onAppear { refresh() }
        .onChange(of: allSpans)       { refresh() }
        .onChange(of: dateRange)      { refresh() }
        .onChange(of: selectedModels) { refresh() }
    }

    private func refresh() {
        dashboardModel.update(spans: allSpans, dateRange: dateRange, selectedModels: selectedModels)
    }

    private func costWidget(_ m: MetricsSummary) -> some View {
        StatWidgetView(
            title: "Total Cost",
            primaryValue: m.totalCostUSD.formatted(.currency(code: "USD")),
            rows: []
        )
    }

    private func tokensWidget(_ m: MetricsSummary) -> some View {
        let total = m.totalInputTokens + m.totalOutputTokens + m.totalCacheReadTokens
        return StatWidgetView(
            title: "Total Tokens",
            primaryValue: total.formatted(.number),
            rows: [
                (label: "Input",      value: m.totalInputTokens.formatted(.number)),
                (label: "Output",     value: m.totalOutputTokens.formatted(.number)),
                (label: "Cache Read", value: m.totalCacheReadTokens.formatted(.number)),
            ]
        )
    }

    private func sessionsWidget(_ m: MetricsSummary) -> some View {
        StatWidgetView(
            title: "Sessions",
            primaryValue: m.sessionCount.formatted(.number),
            rows: []
        )
    }

    private func approvalWidget(_ m: MetricsSummary) -> some View {
        let slices: [PieSlice]
        let centerLabel: String?
        if m.hasApprovalData {
            slices = [
                PieSlice(label: "Approved (\(m.approvalCount))", value: Double(m.approvalCount), color: .green),
                PieSlice(label: "Rejected (\(m.rejectionCount))", value: Double(m.rejectionCount), color: .red),
            ]
            centerLabel = m.approvalRate.map { "\(Int($0 * 100))%" }
        } else {
            slices = []
            centerLabel = nil
        }
        return PieWidgetView(title: "Approval Rate", slices: slices, centerLabel: centerLabel)
    }

    private func modelWidget(_ m: MetricsSummary) -> some View {
        let palette: [Color] = [.blue, .orange, .green, .purple, .teal, .pink]
        let slices = m.modelDistribution.enumerated().map { i, entry in
            PieSlice(
                label: "\(entry.model) (\(entry.requestCount))",
                value: Double(entry.requestCount),
                color: palette[i % palette.count]
            )
        }
        return PieWidgetView(title: "Model Distribution", slices: slices, centerLabel: nil)
    }
}

#Preview {
    MetricsView()
        .modelContainer(
            for: [ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
                  ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self],
            inMemory: true
        )
}
