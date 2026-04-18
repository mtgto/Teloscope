// SPDX-License-Identifier: MIT
import SwiftUI
import SwiftData

struct MetricsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var dashboardModel = MetricsDashboardModel()
    @State private var dateRange: DateInterval = MetricsDashboardModel.defaultDateRange()
    @State private var selectedModels: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                availableModels: dashboardModel.availableModels,
                dateRange: $dateRange,
                selectedModels: $selectedModels,
                isLoading: dashboardModel.isLoading
            )
            .background(.bar)
            Divider()
            Group {
                if let m = dashboardModel.metrics, m.sessionCount > 0 || m.totalInputTokens > 0 {
                    metricsGrid(m)
                        .redacted(reason: dashboardModel.isLoading ? .invalidated : [])
                } else if dashboardModel.isLoading {
                    metricsGrid(nil)
                        .redacted(reason: .placeholder)
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
        .onChange(of: dateRange)      { refresh() }
        .onChange(of: selectedModels) { refresh() }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .otlpSpansIngested) {
                refresh()
            }
        }
    }

    private func refresh() {
        dashboardModel.refresh(
            container: modelContext.container,
            dateRange: dateRange,
            selectedModels: selectedModels
        )
    }

    private func metricsGrid(_ m: MetricsSummary?) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                costWidget(m)
                tokensWidget(m)
                sessionsWidget(m)
                approvalWidget(m)
                modelWidget(m)
                toolRankingWidget(m)
                tokensTimelineWidget(m)
                costTimelineWidget(m)
                requestsTimelineWidget(m)
            }
            .padding(12)
        }
    }

    private func costWidget(_ m: MetricsSummary?) -> some View {
        StatWidgetView(
            title: "Total Cost",
            primaryValue: m?.totalCostUSD.formatted(.currency(code: "USD")) ?? "$0.0000",
            rows: []
        )
    }

    private func tokensWidget(_ m: MetricsSummary?) -> some View {
        let total = m.map { $0.totalInputTokens + $0.totalOutputTokens + $0.totalCacheReadTokens }
        return StatWidgetView(
            title: "Total Tokens",
            primaryValue: total?.formatted(.number) ?? "000,000",
            rows: [
                (label: "Input",      value: m?.totalInputTokens.formatted(.number) ?? "000,000"),
                (label: "Output",     value: m?.totalOutputTokens.formatted(.number) ?? "000,000"),
                (label: "Cache read", value: m?.totalCacheReadTokens.formatted(.number) ?? "000,000"),
            ]
        )
    }

    private func sessionsWidget(_ m: MetricsSummary?) -> some View {
        StatWidgetView(
            title: "Sessions",
            primaryValue: m?.sessionCount.formatted(.number) ?? "000",
            rows: []
        )
    }

    private func approvalWidget(_ m: MetricsSummary?) -> some View {
        let slices: [PieSlice]
        let centerLabel: String?
        if let m, m.hasApprovalData {
            slices = [
                PieSlice(label: "Approved (\(m.approvalCount))", value: Double(m.approvalCount), color: .green),
                PieSlice(label: "Rejected (\(m.rejectionCount))", value: Double(m.rejectionCount), color: .red),
            ]
            centerLabel = m.approvalRate.map { "\(Int($0 * 100))%" }
        } else {
            slices = [
                PieSlice(label: "Approved (\(0))", value: 1, color: .green),
                PieSlice(label: "Rejected (\(0))", value: 1, color: .red),
            ]
            centerLabel = nil
        }
        return PieWidgetView(title: "Approval Rate", slices: slices, centerLabel: centerLabel)
    }

    private func tokensTimelineWidget(_ m: MetricsSummary?) -> some View {
        LineWidgetView(
            title: "Tokens Over Time",
            series: [
                LineSeries(
                    label: String(localized: "Input Tokens"),
                    color: .blue,
                    dataPoints: m?.hourlyTokens.map { (date: $0.date, value: $0.input) } ?? []
                ),
                LineSeries(
                    label: String(localized: "Output Tokens"),
                    color: .green,
                    dataPoints: m?.hourlyTokens.map { (date: $0.date, value: $0.output) } ?? []
                ),
            ],
            yAxisLabel: String(localized: "tokens"),
            granularity: m?.timeGranularity ?? .hourly,
            xDomain: dateRange.start...dateRange.end
        )
    }

    private func costTimelineWidget(_ m: MetricsSummary?) -> some View {
        LineWidgetView(
            title: "Cost Over Time",
            series: [
                LineSeries(
                    label: String(localized: "Cost"),
                    color: .orange,
                    dataPoints: m?.hourlyCost.map { (date: $0.date, value: $0.value) } ?? []
                ),
            ],
            yAxisLabel: "USD",
            granularity: m?.timeGranularity ?? .hourly,
            xDomain: dateRange.start...dateRange.end
        )
    }

    private func requestsTimelineWidget(_ m: MetricsSummary?) -> some View {
        LineWidgetView(
            title: "Requests Over Time",
            series: [
                LineSeries(
                    label: String(localized: "Requests"),
                    color: .purple,
                    dataPoints: m?.hourlyRequests.map { (date: $0.date, value: $0.value) } ?? []
                ),
            ],
            yAxisLabel: String(localized: "requests"),
            granularity: m?.timeGranularity ?? .hourly,
            xDomain: dateRange.start...dateRange.end
        )
    }

    private func toolRankingWidget(_ m: MetricsSummary?) -> some View {
        BarWidgetView(
            title: "Tool Usage",
            items: m?.toolRanking ?? []
        )
    }

    private func modelWidget(_ m: MetricsSummary?) -> some View {
        let palette: [Color] = [.blue, .orange, .green, .purple, .teal, .pink]
        let slices = m?.modelDistribution.enumerated().map { i, entry in
            PieSlice(
                label: "\(entry.model) (\(entry.requestCount))",
                value: Double(entry.requestCount),
                color: palette[i % palette.count]
            )
        } ?? [
            PieSlice(label: "model-name (0)", value: 1, color: .blue),
            PieSlice(label: "model-name (0)", value: 1, color: .orange),
        ]
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
