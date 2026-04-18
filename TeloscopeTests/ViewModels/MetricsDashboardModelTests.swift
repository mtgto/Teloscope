// SPDX-License-Identifier: MIT
import Testing
import SwiftData
import Foundation
@testable import Teloscope

private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
             ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self,
        configurations: config
    )
}

struct MetricsDashboardModelTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private var dateRange: DateInterval {
        DateInterval(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(1))
    }

    private func makeSummary(spans: [OTLPSpan]) -> MetricsSummary {
        MetricsSummary(spans: spans.map { SpanSnapshot($0) }, dateRange: dateRange)
    }

    @Test func tokenTotalsAreSummed() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            model: "claude-opus-4", inputTokens: 100, outputTokens: 50, cacheReadTokens: 20))
        ctx.insert(OTLPSpan(traceId: "t2", spanId: "s2",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            model: "claude-sonnet-4", inputTokens: 200, outputTokens: 80, cacheReadTokens: 10))
        try ctx.save()
        let s = makeSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(s.totalInputTokens == 300)
        #expect(s.totalOutputTokens == 130)
        #expect(s.totalCacheReadTokens == 30)
    }

    @Test func sessionCountDeduplicates() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            sessionId: "A"))
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s2",
            name: "claude_code.tool",
            startTime: now, endTime: now.addingTimeInterval(1),
            sessionId: "A"))
        ctx.insert(OTLPSpan(traceId: "t2", spanId: "s3",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            sessionId: "B"))
        try ctx.save()
        let spans = try ctx.fetch(FetchDescriptor<OTLPSpan>())
        #expect(makeSummary(spans: spans).sessionCount == 2)
    }

    @Test func approvalRateCalculated() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.tool.blocked_on_user",
            startTime: now, endTime: now.addingTimeInterval(1),
            decision: "accept"))
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s2",
            name: "claude_code.tool.blocked_on_user",
            startTime: now, endTime: now.addingTimeInterval(1),
            decision: "reject"))
        try ctx.save()
        let s = makeSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(s.hasApprovalData)
        #expect(s.approvalCount == 1)
        #expect(s.rejectionCount == 1)
        #expect(s.approvalRate == 0.5)
    }

    @Test func approvalRateNilWithNoData() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1)))
        try ctx.save()
        let s = makeSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(!s.hasApprovalData)
        #expect(s.approvalRate == nil)
    }

    @Test func modelDistributionSortedByCount() throws {
        let ctx = ModelContext(try makeContainer())
        for (id, model) in [("s1", "claude-opus-4"), ("s2", "claude-sonnet-4"), ("s3", "claude-sonnet-4")] {
            ctx.insert(OTLPSpan(traceId: "t1", spanId: id,
                name: "claude_code.llm_request",
                startTime: now, endTime: now.addingTimeInterval(1),
                model: model))
        }
        try ctx.save()
        let s = makeSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(s.modelDistribution.count == 2)
        #expect(s.modelDistribution[0].model == "claude-sonnet-4")
        #expect(s.modelDistribution[0].requestCount == 2)
    }

    @Test func costCalculatedFromPricing() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            model: "claude-opus-4", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0))
        try ctx.save()
        let s = makeSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(abs(s.totalCostUSD - 15.0) < 0.001)
    }

    @Test func unknownModelZeroCost() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            model: "unknown-model", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0))
        try ctx.save()
        let s = makeSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(s.totalCostUSD == 0.0)
    }
}
