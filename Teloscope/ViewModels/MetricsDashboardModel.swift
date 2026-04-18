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
    private var computeTask: Task<Void, Never>?

    func refresh(container: ModelContainer, dateRange: DateInterval, selectedModels: Set<String>) {
        if repository == nil {
            repository = MetricsRepository(modelContainer: container)
        }
        computeTask?.cancel()
        isLoading = true
        computeTask = Task {
            do {
                let result = try await repository!.computeSummary(
                    dateRange: dateRange,
                    selectedModels: selectedModels
                )
                guard !Task.isCancelled else { return }
                availableModels = result.availableModels
                metrics = result.summary
            } catch {
                guard !Task.isCancelled else { return }
            }
            isLoading = false
        }
    }

    static func defaultDateRange() -> DateInterval {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now.addingTimeInterval(-7 * 24 * 3600))
        return DateInterval(start: start, end: now)
    }
}
