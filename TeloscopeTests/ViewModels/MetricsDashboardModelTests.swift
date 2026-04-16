// SPDX-License-Identifier: MIT
import Testing
import SwiftData
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

    @Test func tokenTotalsAreSummed() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [
                SpanAttribute(key: "input_tokens",      value: .int64(100)),
                SpanAttribute(key: "output_tokens",     value: .int64(50)),
                SpanAttribute(key: "cache_read_tokens", value: .int64(20)),
                SpanAttribute(key: "model",             value: .string("claude-opus-4")),
            ]))
        ctx.insert(OTLPSpan(traceId: "t2", spanId: "s2",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [
                SpanAttribute(key: "input_tokens",      value: .int64(200)),
                SpanAttribute(key: "output_tokens",     value: .int64(80)),
                SpanAttribute(key: "cache_read_tokens", value: .int64(10)),
                SpanAttribute(key: "model",             value: .string("claude-sonnet-4")),
            ]))
        try ctx.save()
        let spans = try ctx.fetch(FetchDescriptor<OTLPSpan>())
        let s = MetricsSummary(spans: spans)
        #expect(s.totalInputTokens == 300)
        #expect(s.totalOutputTokens == 130)
        #expect(s.totalCacheReadTokens == 30)
    }

    @Test func sessionCountDeduplicates() throws {
        let ctx = ModelContext(try makeContainer())
        // Two spans same session
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [SpanAttribute(key: "session.id", value: .string("A"))]))
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s2",
            name: "claude_code.tool",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [SpanAttribute(key: "session.id", value: .string("A"))]))
        // One span different session
        ctx.insert(OTLPSpan(traceId: "t2", spanId: "s3",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [SpanAttribute(key: "session.id", value: .string("B"))]))
        try ctx.save()
        let spans = try ctx.fetch(FetchDescriptor<OTLPSpan>())
        #expect(MetricsSummary(spans: spans).sessionCount == 2)
    }

    @Test func approvalRateCalculated() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.tool.blocked_on_user",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [SpanAttribute(key: "decision", value: .string("accept"))]))
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s2",
            name: "claude_code.tool.blocked_on_user",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [SpanAttribute(key: "decision", value: .string("reject"))]))
        try ctx.save()
        let s = MetricsSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(s.hasApprovalData)
        #expect(s.approvalCount == 1)
        #expect(s.rejectionCount == 1)
        #expect(s.approvalRate == 0.5)
    }

    @Test func approvalRateNilWithNoData() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1), attributes: []))
        try ctx.save()
        let s = MetricsSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(!s.hasApprovalData)
        #expect(s.approvalRate == nil)
    }

    @Test func modelDistributionSortedByCount() throws {
        let ctx = ModelContext(try makeContainer())
        for (id, model) in [("s1","claude-opus-4"), ("s2","claude-sonnet-4"), ("s3","claude-sonnet-4")] {
            ctx.insert(OTLPSpan(traceId: "t1", spanId: id,
                name: "claude_code.llm_request",
                startTime: now, endTime: now.addingTimeInterval(1),
                attributes: [SpanAttribute(key: "model", value: .string(model))]))
        }
        try ctx.save()
        let s = MetricsSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(s.modelDistribution.count == 2)
        #expect(s.modelDistribution[0].model == "claude-sonnet-4")
        #expect(s.modelDistribution[0].requestCount == 2)
    }

    @Test func costCalculatedFromPricing() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [
                SpanAttribute(key: "input_tokens",      value: .int64(1_000_000)),
                SpanAttribute(key: "output_tokens",     value: .int64(0)),
                SpanAttribute(key: "cache_read_tokens", value: .int64(0)),
                SpanAttribute(key: "model",             value: .string("claude-opus-4")),
            ]))
        try ctx.save()
        let s = MetricsSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(abs(s.totalCostUSD - 15.0) < 0.001)
    }

    @Test func unknownModelZeroCost() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [
                SpanAttribute(key: "input_tokens", value: .int64(1_000_000)),
                SpanAttribute(key: "output_tokens", value: .int64(0)),
                SpanAttribute(key: "cache_read_tokens", value: .int64(0)),
                SpanAttribute(key: "model", value: .string("unknown-model")),
            ]))
        try ctx.save()
        let s = MetricsSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(s.totalCostUSD == 0.0)
    }
}
