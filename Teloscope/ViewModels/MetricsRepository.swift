// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@ModelActor
actor MetricsRepository {
    func computeSummary(
        dateRange: DateInterval,
        selectedModels: Set<String>
    ) throws -> (availableModels: [String], summary: MetricsSummary) {
        let start = dateRange.start
        let end = dateRange.end

        let spanDescriptor = FetchDescriptor<OTLPSpan>(
            predicate: #Predicate { $0.startTime >= start && $0.startTime <= end }
        )
        let fetched = try modelContext.fetch(spanDescriptor)
        let dateFiltered = fetched.map { SpanSnapshot($0) }

        let modelSet = Set(dateFiltered.compactMap { snap -> String? in
            guard snap.name.hasPrefix("claude_code.llm_request") else { return nil }
            return snap.model
        })
        let availableModels = modelSet.sorted()

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

        let logDescriptor = FetchDescriptor<LogEvent>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp <= end }
        )
        let logEvents = try modelContext.fetch(logDescriptor).map { LogEventSnapshot($0) }

        let metricDescriptor = FetchDescriptor<OTLPNumberDataPoint>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp <= end }
        )
        let numberDataPoints = try modelContext.fetch(metricDescriptor).map { NumberDataPointSnapshot($0) }

        return (availableModels, MetricsSummary(spans: filtered, logEvents: logEvents, numberDataPoints: numberDataPoints, dateRange: dateRange))
    }
}
