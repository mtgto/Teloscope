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
                if let m = dashboardModel.metrics, m.sessionCount > 0 || m.totalInputTokens > 0 {
                    metricsGrid(m, isLoading: false)
                } else if dashboardModel.isLoading {
                    metricsGrid(nil, isLoading: true)
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
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if dashboardModel.isLoading, dashboardModel.metrics != nil {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: allSpans)       { refresh() }
        .onChange(of: dateRange)      { refresh() }
        .onChange(of: selectedModels) { refresh() }
    }

    private func refresh() {
        dashboardModel.update(spans: allSpans, dateRange: dateRange, selectedModels: selectedModels)
    }

    private func metricsGrid(_ m: MetricsSummary?, isLoading: Bool) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                costWidget(m, isLoading: isLoading)
                tokensWidget(m, isLoading: isLoading)
                sessionsWidget(m, isLoading: isLoading)
                approvalWidget(m, isLoading: isLoading)
                modelWidget(m, isLoading: isLoading)
            }
            .padding(12)
        }
        .allowsHitTesting(!isLoading)
    }

    private func costWidget(_ m: MetricsSummary?, isLoading: Bool) -> some View {
        StatWidgetView(
            title: "Total Cost",
            primaryValue: m?.totalCostUSD.formatted(.currency(code: "USD")) ?? "$0.0000",
            rows: [],
            isLoading: isLoading
        )
    }

    private func tokensWidget(_ m: MetricsSummary?, isLoading: Bool) -> some View {
        let total = m.map { $0.totalInputTokens + $0.totalOutputTokens + $0.totalCacheReadTokens }
        return StatWidgetView(
            title: "Total Tokens",
            primaryValue: total?.formatted(.number) ?? "000,000",
            rows: [
                (label: "Input",      value: m?.totalInputTokens.formatted(.number) ?? "000,000"),
                (label: "Output",     value: m?.totalOutputTokens.formatted(.number) ?? "000,000"),
                (label: "Cache Read", value: m?.totalCacheReadTokens.formatted(.number) ?? "000,000"),
            ],
            isLoading: isLoading
        )
    }

    private func sessionsWidget(_ m: MetricsSummary?, isLoading: Bool) -> some View {
        StatWidgetView(
            title: "Sessions",
            primaryValue: m?.sessionCount.formatted(.number) ?? "000",
            rows: [],
            isLoading: isLoading
        )
    }

    private func approvalWidget(_ m: MetricsSummary?, isLoading: Bool) -> some View {
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
                PieSlice(label: "Approved (00)", value: 1, color: .green),
                PieSlice(label: "Rejected (00)", value: 1, color: .red),
            ]
            centerLabel = nil
        }
        return PieWidgetView(title: "Approval Rate", slices: slices, centerLabel: centerLabel, isLoading: isLoading)
    }

    private func modelWidget(_ m: MetricsSummary?, isLoading: Bool) -> some View {
        let palette: [Color] = [.blue, .orange, .green, .purple, .teal, .pink]
        let slices = m?.modelDistribution.enumerated().map { i, entry in
            PieSlice(
                label: "\(entry.model) (\(entry.requestCount))",
                value: Double(entry.requestCount),
                color: palette[i % palette.count]
            )
        } ?? [
            PieSlice(label: "model-name (00)", value: 1, color: .blue),
            PieSlice(label: "model-name (00)", value: 1, color: .orange),
        ]
        return PieWidgetView(title: "Model Distribution", slices: slices, centerLabel: nil, isLoading: isLoading)
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
