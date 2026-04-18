// SPDX-License-Identifier: MIT
import Foundation

/// Lightweight, Sendable snapshot of an OTLPSpan used for off-main-thread computation.
/// Uses the typed columns on OTLPSpan directly — no JSON decoding, no relationship faults.
struct SpanSnapshot: Sendable {
    let name: String
    let startTime: Date
    let sessionId: String?
    let model: String?
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheReadTokens: Int64
    let decision: String?

    init(_ span: OTLPSpan) {
        name = span.name
        startTime = span.startTime
        sessionId = span.sessionId
        model = span.model
        inputTokens = span.inputTokens ?? 0
        outputTokens = span.outputTokens ?? 0
        cacheReadTokens = span.cacheReadTokens ?? 0
        decision = span.decision
    }
}

enum TimeGranularity {
    case hourly  // date range ≤ 2 days: 1-hour buckets
    case daily   // date range ≤ 30 days: 1-day buckets
    case weekly  // date range > 30 days: 1-week buckets

    var calendarComponent: Calendar.Component {
        switch self {
        case .hourly: .hour
        case .daily: .day
        case .weekly: .weekOfYear
        }
    }

    static func from(dateRange: DateInterval) -> TimeGranularity {
        let days = dateRange.duration / 86400
        if days <= 2 { return .hourly }
        if days <= 30 { return .daily }
        return .weekly
    }
}

struct MetricsSummary {
    let totalCostUSD: Double
    let totalInputTokens: Int64
    let totalOutputTokens: Int64
    let totalCacheReadTokens: Int64
    let sessionCount: Int
    let approvalCount: Int
    let rejectionCount: Int
    let hasApprovalData: Bool
    let modelDistribution: [(model: String, requestCount: Int)]
    let toolRanking: [(name: String, count: Int)]
    let usageHeatmap: [(weekday: Int, hour: Int, count: Int)]
    let timeGranularity: TimeGranularity
    let hourlyTokens: [(date: Date, input: Double, output: Double)]
    let hourlyCost: [(date: Date, value: Double)]
    let hourlyRequests: [(date: Date, value: Double)]

    var approvalRate: Double? {
        let total = approvalCount + rejectionCount
        guard total > 0 else { return nil }
        return Double(approvalCount) / Double(total)
    }

    init(spans: [SpanSnapshot], dateRange: DateInterval) {
        var costUSD = 0.0
        var inputTokens: Int64 = 0
        var outputTokens: Int64 = 0
        var cacheReadTokens: Int64 = 0
        var sessionIds: Set<String> = []
        var approved = 0
        var rejected = 0
        var hasDecisions = false
        var modelCounts: [String: Int] = [:]
        var toolCounts: [String: Int] = [:]
        var heatCounts: [Int: [Int: Int]] = [:]

        for span in spans {
            if let sid = span.sessionId { sessionIds.insert(sid) }

            if span.name == "claude_code.llm_request" {
                inputTokens     += span.inputTokens
                outputTokens    += span.outputTokens
                cacheReadTokens += span.cacheReadTokens
                let wd = Calendar.current.component(.weekday, from: span.startTime)
                let hr = Calendar.current.component(.hour,    from: span.startTime)
                heatCounts[wd, default: [:]][hr, default: 0] += 1
                if let model = span.model {
                    modelCounts[model, default: 0] += 1
                    if let p = ModelPricing.pricing(for: model) {
                        costUSD += p.cost(
                            inputTokens: span.inputTokens,
                            outputTokens: span.outputTokens,
                            cacheReadTokens: span.cacheReadTokens
                        )
                    }
                }
            } else if span.name.hasPrefix("claude_code.tool.blocked_on_user") {
                hasDecisions = true
                switch span.decision?.lowercased() {
                case "accept": approved += 1
                case "reject": rejected += 1
                default: break
                }
            } else if span.name.hasPrefix("claude_code.tool.") {
                let toolName = String(span.name.dropFirst("claude_code.tool.".count))
                toolCounts[toolName, default: 0] += 1
            }
        }

        self.totalCostUSD         = costUSD
        self.totalInputTokens     = inputTokens
        self.totalOutputTokens    = outputTokens
        self.totalCacheReadTokens = cacheReadTokens
        self.sessionCount         = sessionIds.count
        self.approvalCount        = approved
        self.rejectionCount       = rejected
        self.hasApprovalData      = hasDecisions
        self.modelDistribution    = modelCounts
            .sorted { $0.value > $1.value }
            .map { (model: $0.key, requestCount: $0.value) }
        self.toolRanking = toolCounts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (name: $0.key, count: $0.value) }
        let heatmapEntries = heatCounts.flatMap { wd, hours in
            hours.map { hr, cnt in (weekday: wd, hour: hr, count: cnt) }
        }
        self.usageHeatmap = heatmapEntries.sorted { lhs, rhs in
            lhs.weekday != rhs.weekday ? lhs.weekday < rhs.weekday : lhs.hour < rhs.hour
        }

        // Build time series data bucketed by granularity
        let granularity = TimeGranularity.from(dateRange: dateRange)
        let component = granularity.calendarComponent
        let cal = Calendar.current

        var tokenBuckets: [Date: (input: Double, output: Double)] = [:]
        var costBuckets: [Date: Double] = [:]
        var requestBuckets: [Date: Double] = [:]

        for span in spans where span.name == "claude_code.llm_request" {
            guard let bucketStart = cal.dateInterval(of: component, for: span.startTime)?.start else { continue }
            let input  = Double(span.inputTokens)
            let output = Double(span.outputTokens)
            let existing = tokenBuckets[bucketStart] ?? (input: 0, output: 0)
            tokenBuckets[bucketStart] = (input: existing.input + input, output: existing.output + output)
            requestBuckets[bucketStart, default: 0] += 1
            if let model = span.model, let p = ModelPricing.pricing(for: model) {
                costBuckets[bucketStart, default: 0] += p.cost(
                    inputTokens: span.inputTokens,
                    outputTokens: span.outputTokens,
                    cacheReadTokens: span.cacheReadTokens
                )
            }
        }

        // Enumerate all buckets in range, filling zeros for empty slots
        var allBucketDates: [Date] = []
        if let firstBucket = cal.dateInterval(of: component, for: dateRange.start)?.start {
            var current = firstBucket
            while current < dateRange.end {
                allBucketDates.append(current)
                guard let next = cal.date(byAdding: component, value: 1, to: current) else { break }
                current = next
            }
        }

        self.timeGranularity = granularity
        self.hourlyTokens = allBucketDates.compactMap { date in
            guard let v = tokenBuckets[date] else { return nil }
            return (date: date, input: v.input, output: v.output)
        }
        self.hourlyCost = allBucketDates.compactMap { date in
            costBuckets[date].map { (date: date, value: $0) }
        }
        self.hourlyRequests = allBucketDates.compactMap { date in
            requestBuckets[date].map { (date: date, value: $0) }
        }
    }
}
