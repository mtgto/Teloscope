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
                if let m = dashboardModel.metrics {
                    if m.sessionCount > 0 || m.totalInputTokens > 0 {
                        metricsGrid(m)
                            .redacted(reason: dashboardModel.isLoading ? .invalidated : [])
                    } else if !dashboardModel.isLoading {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("No spans recorded in the selected range.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
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
        .task {
            for await _ in NotificationCenter.default.notifications(named: .otlpLogsIngested) {
                refresh()
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .otlpMetricsIngested) {
                refresh()
            }
        }
    }

    private func refresh() {
        let effectiveRange = DateInterval(start: dateRange.start, end: max(dateRange.end, Date()))
        dashboardModel.refresh(
            container: modelContext.container,
            dateRange: effectiveRange,
            selectedModels: selectedModels
        )
    }

    private func metricsGrid(_ m: MetricsSummary?) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                costWidget(m)
                tokensWidget(m)
                sessionsWidget(m)
                linesOfCodeWidget(m)
                approvalWidget(m)
                modelWidget(m)
                toolRankingWidget(m)
                userSkillRankingWidget(m)
                claudeSkillRankingWidget(m)
                usageHeatmapWidget(m)
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

    private func linesOfCodeWidget(_ m: MetricsSummary?) -> some View {
        let total = m.map { $0.linesOfCodeAdded + $0.linesOfCodeRemoved }
        return StatWidgetView(
            title: "Lines of Code",
            primaryValue: total?.formatted(.number) ?? "000",
            rows: [
                (label: "Added",   value: m?.linesOfCodeAdded.formatted(.number)   ?? "000"),
                (label: "Removed", value: m?.linesOfCodeRemoved.formatted(.number) ?? "000"),
            ]
        )
    }

    private func approvalWidget(_ m: MetricsSummary?) -> some View {
        let slices: [PieSlice]
        let centerLabel: String?
        if let m, m.hasApprovalData {
            var s = [
                PieSlice(label: "Approved (\(m.approvalCount))", value: Double(m.approvalCount), color: .green),
                PieSlice(label: "Rejected (\(m.rejectionCount))", value: Double(m.rejectionCount), color: .red),
            ]
            if m.unknownCount > 0 {
                s.append(PieSlice(label: "Unknown (\(m.unknownCount))", value: Double(m.unknownCount), color: .gray))
            }
            slices = s
            centerLabel = m.approvalRate.map { "\(Int($0 * 100))%" }
        } else {
            slices = []
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
            yAxisLabel: String(localized: "Token Count"),
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
            yAxisLabel: String(localized: "Request Count"),
            granularity: m?.timeGranularity ?? .hourly,
            xDomain: dateRange.start...dateRange.end
        )
    }

    private func usageHeatmapWidget(_ m: MetricsSummary?) -> some View {
        HeatmapWidgetView(
            title: "Usage by Time",
            data: m?.usageHeatmap ?? []
        )
    }

    private func toolRankingWidget(_ m: MetricsSummary?) -> some View {
        BarWidgetView(
            title: "Tool Usage",
            items: m?.toolRanking ?? []
        )
    }

    private func userSkillRankingWidget(_ m: MetricsSummary?) -> some View {
        BarWidgetView(
            title: "User Skill Usage",
            items: m?.userSkillRanking ?? []
        )
    }

    private func claudeSkillRankingWidget(_ m: MetricsSummary?) -> some View {
        BarWidgetView(
            title: "Claude Skill Usage",
            items: m?.claudeSkillRanking ?? []
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
        } ?? []
        return PieWidgetView(title: "Model Distribution", slices: slices, centerLabel: nil)
    }
}

#Preview {
    MetricsView()
        .modelContainer(
            for: [ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
                  ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self,
                  OTLPNumberDataPoint.self],
            inMemory: true
        )
}
