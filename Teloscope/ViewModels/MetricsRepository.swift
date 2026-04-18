// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@ModelActor
actor MetricsRepository {
    func computeSummary(
        dateRange: DateInterval,
        selectedModels: Set<String>
    ) throws -> (availableModels: [String], summary: MetricsSummary) {
        // Apply the date filter in SQL so only matching spans are loaded from disk.
        let start = dateRange.start
        let end = dateRange.end
        let descriptor = FetchDescriptor<OTLPSpan>(
            predicate: #Predicate { $0.startTime >= start && $0.startTime <= end }
        )
        let fetched = try modelContext.fetch(descriptor)

        // Convert to Sendable snapshots using the typed columns on OTLPSpan — no JSON decoding.
        let dateFiltered = fetched.map { SpanSnapshot($0) }

        // Derive model list from date-filtered spans only (ignores model filter so
        // the picker doesn't empty when all models are deselected).
        let modelSet = Set(dateFiltered.compactMap { snap -> String? in
            guard snap.name.hasPrefix("claude_code.llm_request") else { return nil }
            return snap.model
        })
        let availableModels = modelSet.sorted()

        // Model filter applies only to LLM request spans.
        let filtered: [SpanSnapshot]
        if selectedModels.isEmpty {
            filtered = dateFiltered
        } else {
            filtered = dateFiltered.filter { snap in
                guard snap.name.hasPrefix("claude_code.llm_request") else { return true }
                guard let m = snap.model else { return false }
                return selectedModels.contains(m)
            }
        }

        return (availableModels, MetricsSummary(spans: filtered, dateRange: dateRange))
    }
}
