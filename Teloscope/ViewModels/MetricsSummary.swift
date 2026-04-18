// SPDX-License-Identifier: MIT
import Foundation

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
    let timeGranularity: TimeGranularity
    let hourlyTokens: [(date: Date, input: Double, output: Double)]
    let hourlyCost: [(date: Date, value: Double)]
    let hourlyRequests: [(date: Date, value: Double)]

    var approvalRate: Double? {
        let total = approvalCount + rejectionCount
        guard total > 0 else { return nil }
        return Double(approvalCount) / Double(total)
    }

    init(spans: [OTLPSpan], dateRange: DateInterval) {
        var costUSD = 0.0
        var inputTokens: Int64 = 0
        var outputTokens: Int64 = 0
        var cacheReadTokens: Int64 = 0
        var sessionIds: Set<String> = []
        var approved = 0
        var rejected = 0
        var hasDecisions = false
        var modelCounts: [String: Int] = [:]

        for span in spans {
            if let sid = Self.stringAttr(span, "session.id") {
                sessionIds.insert(sid)
            }
            if span.name.hasPrefix("claude_code.llm_request") {
                let input     = Self.int64Attr(span, "input_tokens")      ?? 0
                let output    = Self.int64Attr(span, "output_tokens")     ?? 0
                let cacheRead = Self.int64Attr(span, "cache_read_tokens") ?? 0
                inputTokens     += input
                outputTokens    += output
                cacheReadTokens += cacheRead
                if let model = Self.stringAttr(span, "model") {
                    modelCounts[model, default: 0] += 1
                    if let p = ModelPricing.pricing(for: model) {
                        costUSD += p.cost(inputTokens: input, outputTokens: output, cacheReadTokens: cacheRead)
                    }
                }
            } else if span.name.hasPrefix("claude_code.tool.blocked_on_user") {
                hasDecisions = true
                switch Self.stringAttr(span, "decision")?.lowercased() {
                case "accept": approved += 1
                case "reject": rejected += 1
                default: break
                }
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

        // Build time series data bucketed by granularity
        let granularity = TimeGranularity.from(dateRange: dateRange)
        let component = granularity.calendarComponent
        let cal = Calendar.current

        var tokenBuckets: [Date: (input: Double, output: Double)] = [:]
        var costBuckets: [Date: Double] = [:]
        var requestBuckets: [Date: Double] = [:]

        for span in spans where span.name.hasPrefix("claude_code.llm_request") {
            guard let bucketStart = cal.dateInterval(of: component, for: span.startTime)?.start else { continue }
            let input     = Double(Self.int64Attr(span, "input_tokens")  ?? 0)
            let output    = Double(Self.int64Attr(span, "output_tokens") ?? 0)
            let cacheRead = Self.int64Attr(span, "cache_read_tokens")     ?? 0
            let existing = tokenBuckets[bucketStart] ?? (input: 0, output: 0)
            tokenBuckets[bucketStart] = (input: existing.input + input, output: existing.output + output)
            requestBuckets[bucketStart, default: 0] += 1
            if let model = Self.stringAttr(span, "model"), let p = ModelPricing.pricing(for: model) {
                costBuckets[bucketStart, default: 0] += p.cost(
                    inputTokens: Int64(input), outputTokens: Int64(output), cacheReadTokens: cacheRead
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
        self.hourlyTokens = allBucketDates.map { date in
            let v = tokenBuckets[date] ?? (input: 0, output: 0)
            return (date: date, input: v.input, output: v.output)
        }
        self.hourlyCost = allBucketDates.map { date in
            (date: date, value: costBuckets[date] ?? 0)
        }
        self.hourlyRequests = allBucketDates.map { date in
            (date: date, value: requestBuckets[date] ?? 0)
        }
    }

    private static func int64Attr(_ span: OTLPSpan, _ key: String) -> Int64? {
        guard case .int64(let v) = span.attributes.first(where: { $0.key == key })?.value else { return nil }
        return v
    }

    private static func stringAttr(_ span: OTLPSpan, _ key: String) -> String? {
        guard case .string(let v) = span.attributes.first(where: { $0.key == key })?.value else { return nil }
        return v
    }
}
