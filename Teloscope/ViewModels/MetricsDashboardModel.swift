// SPDX-License-Identifier: MIT
import Foundation
import Observation

@Observable
@MainActor
final class MetricsDashboardModel {
    private(set) var availableModels: [String] = []
    private(set) var metrics: MetricsSummary?
    private(set) var isLoading = false

    private var computeTask: Task<Void, Never>?

    func update(spans: [OTLPSpan], dateRange: DateInterval, selectedModels: Set<String>) {
        computeTask?.cancel()
        isLoading = true
        computeTask = Task { @MainActor in
            // Yield so SwiftUI renders the loading state before we start computing.
            await Task.yield()
            guard !Task.isCancelled else { return }

            let dateFiltered = spans.filter { dateRange.contains($0.startTime) }

            // Derive model list from date-filtered spans only (ignores model filter so
            // the picker doesn't empty when all models are deselected).
            let modelSet = Set(dateFiltered.compactMap { span -> String? in
                guard span.name.hasPrefix("claude_code.llm_request") else { return nil }
                guard case .string(let m) = span.attributes.first(where: { $0.key == "model" })?.value else { return nil }
                return m
            })
            availableModels = modelSet.sorted()

            // Model filter applies only to LLM request spans.
            let filtered: [OTLPSpan]
            if selectedModels.isEmpty {
                filtered = dateFiltered
            } else {
                filtered = dateFiltered.filter { span in
                    guard span.name.hasPrefix("claude_code.llm_request") else { return true }
                    guard case .string(let m) = span.attributes.first(where: { $0.key == "model" })?.value else { return false }
                    return selectedModels.contains(m)
                }
            }

            guard !Task.isCancelled else { return }
            metrics = MetricsSummary(spans: filtered, dateRange: dateRange)
            isLoading = false
        }
    }

    static func defaultDateRange() -> DateInterval {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now.addingTimeInterval(-7 * 24 * 3600))
        return DateInterval(start: start, end: now)
    }
}
