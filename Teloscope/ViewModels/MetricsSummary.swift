// SPDX-License-Identifier: MIT
import Foundation

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

    var approvalRate: Double? {
        let total = approvalCount + rejectionCount
        guard total > 0 else { return nil }
        return Double(approvalCount) / Double(total)
    }

    init(spans: [OTLPSpan]) {
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
