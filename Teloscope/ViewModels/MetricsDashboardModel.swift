// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class MetricsDashboardModel {
    private(set) var availableModels: [String] = []
    private(set) var metrics: MetricsSummary?
    private(set) var isLoading = false

    private var repository: MetricsRepository?
    private var isComputing = false
    private var pendingRequest: (dateRange: DateInterval, selectedModels: Set<String>)?

    // Coalesces overlapping refresh requests: since `MetricsRepository.computeSummary`
    // can't be cancelled mid-flight (it's a synchronous SwiftData fetch inside an actor),
    // rapid-fire calls (e.g. from bursty OTLP ingestion notifications) would otherwise
    // queue up on the actor and pin the CPU running summaries whose results are immediately
    // discarded. Instead, a request made while one is already running just replaces the
    // pending one, so at most one extra computation runs after the in-flight one finishes.
    func refresh(container: ModelContainer, dateRange: DateInterval, selectedModels: Set<String>) {
        if repository == nil {
            repository = MetricsRepository(modelContainer: container)
        }
        pendingRequest = (dateRange, selectedModels)
        guard !isComputing else { return }
        isLoading = true
        runNextPendingRequest()
    }

    private func runNextPendingRequest() {
        guard let request = pendingRequest else {
            isComputing = false
            isLoading = false
            return
        }
        pendingRequest = nil
        isComputing = true
        Task {
            do {
                let result = try await repository!.computeSummary(
                    dateRange: request.dateRange,
                    selectedModels: request.selectedModels
                )
                availableModels = result.availableModels
                metrics = result.summary
            } catch {}
            runNextPendingRequest()
        }
    }

    static func defaultDateRange() -> DateInterval {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now.addingTimeInterval(-7 * 24 * 3600))
        return DateInterval(start: start, end: now)
    }
}
