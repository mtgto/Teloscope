// SPDX-License-Identifier: MIT
import Testing
import SwiftData
import Foundation
@testable import Teloscope

struct MetricsRepositoryTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
                 ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self, LogEvent.self,
            configurations: config
        )
    }

    // MARK: - Date range filtering

    @Test func spansOutsideDateRangeAreExcluded() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "in",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            model: "claude-opus-4", inputTokens: 100, outputTokens: 0, cacheReadTokens: 0))
        ctx.insert(OTLPSpan(traceId: "t2", spanId: "out",
            name: "claude_code.llm_request",
            startTime: now.addingTimeInterval(-7200), endTime: now.addingTimeInterval(-7199),
            model: "claude-opus-4", inputTokens: 999, outputTokens: 0, cacheReadTokens: 0))
        try ctx.save()

        let repo = MetricsRepository(modelContainer: container)
        let range = DateInterval(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(1))
        let (_, summary) = try await repo.computeSummary(dateRange: range, selectedModels: [])
        #expect(summary.totalInputTokens == 100)
    }

    @Test func emptyRangeReturnsZeroSummary() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            model: "claude-opus-4", inputTokens: 100, outputTokens: 50, cacheReadTokens: 0))
        try ctx.save()

        let repo = MetricsRepository(modelContainer: container)
        // Range that does not include the span
        let range = DateInterval(start: now.addingTimeInterval(10), end: now.addingTimeInterval(20))
        let (models, summary) = try await repo.computeSummary(dateRange: range, selectedModels: [])
        #expect(models.isEmpty)
        #expect(summary.totalInputTokens == 0)
        #expect(summary.sessionCount == 0)
    }

    // MARK: - Available models

    @Test func availableModelsReflectsDateFilteredSpans() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            model: "claude-opus-4", inputTokens: 10, outputTokens: 0, cacheReadTokens: 0))
        // Outside date range — should not appear in availableModels
        ctx.insert(OTLPSpan(traceId: "t2", spanId: "s2",
            name: "claude_code.llm_request",
            startTime: now.addingTimeInterval(-7200), endTime: now.addingTimeInterval(-7199),
            model: "claude-haiku-4", inputTokens: 10, outputTokens: 0, cacheReadTokens: 0))
        try ctx.save()

        let repo = MetricsRepository(modelContainer: container)
        let range = DateInterval(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(1))
        let (models, _) = try await repo.computeSummary(dateRange: range, selectedModels: [])
        #expect(models == ["claude-opus-4"])
    }

    @Test func availableModelsSortedAlphabetically() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        for (id, model) in [("s1", "claude-sonnet-4"), ("s2", "claude-opus-4"), ("s3", "claude-haiku-4")] {
            ctx.insert(OTLPSpan(traceId: "t1", spanId: id,
                name: "claude_code.llm_request",
                startTime: now, endTime: now.addingTimeInterval(1),
                model: model, inputTokens: 1, outputTokens: 0, cacheReadTokens: 0))
        }
        try ctx.save()

        let repo = MetricsRepository(modelContainer: container)
        let range = DateInterval(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(1))
        let (models, _) = try await repo.computeSummary(dateRange: range, selectedModels: [])
        #expect(models == ["claude-haiku-4", "claude-opus-4", "claude-sonnet-4"])
    }

    // MARK: - Model filter

    @Test func modelFilterRestrictsLLMRequestSpans() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            model: "claude-opus-4", inputTokens: 100, outputTokens: 0, cacheReadTokens: 0))
        ctx.insert(OTLPSpan(traceId: "t2", spanId: "s2",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            model: "claude-sonnet-4", inputTokens: 200, outputTokens: 0, cacheReadTokens: 0))
        try ctx.save()

        let repo = MetricsRepository(modelContainer: container)
        let range = DateInterval(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(1))
        let (_, summary) = try await repo.computeSummary(dateRange: range, selectedModels: ["claude-opus-4"])
        #expect(summary.totalInputTokens == 100)
    }

    @Test func modelFilterPassesNonLLMSpansThrough() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        // LLM request that won't pass filter
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            sessionId: "A", model: "claude-haiku-4", inputTokens: 0, outputTokens: 0, cacheReadTokens: 0))
        // tool span (no model) — must still count toward session
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s2",
            name: "claude_code.tool",
            startTime: now, endTime: now.addingTimeInterval(1),
            sessionId: "A"))
        try ctx.save()

        let repo = MetricsRepository(modelContainer: container)
        let range = DateInterval(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(1))
        // Filter selects only opus; haiku LLM span excluded, but tool span passes through
        let (_, summary) = try await repo.computeSummary(dateRange: range, selectedModels: ["claude-opus-4"])
        #expect(summary.sessionCount == 1)
    }

    // MARK: - Skill ranking

    @Test func skillRankingIncludesLogEventsInDateRange() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(LogEvent(
            eventName: "skill_activated",
            timestamp: now,
            skillName: "superpowers:brainstorming"
        ))
        ctx.insert(LogEvent(
            eventName: "user_prompt",
            timestamp: now,
            skillName: "otel-test",
            invocationTrigger: "user-slash"
        ))
        ctx.insert(LogEvent(
            eventName: "skill_activated",
            timestamp: now.addingTimeInterval(-7200), // outside range
            skillName: "update-config"
        ))
        try ctx.save()

        let repo = MetricsRepository(modelContainer: container)
        let range = DateInterval(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(1))
        let (_, summary) = try await repo.computeSummary(dateRange: range, selectedModels: [])
        #expect(summary.claudeSkillRanking.count == 1)
        #expect(summary.claudeSkillRanking[0].name == "superpowers:brainstorming")
        #expect(summary.userSkillRanking.count == 1)
        #expect(summary.userSkillRanking[0].name == "otel-test")
    }

    // MARK: - Multiple spans aggregation

    @Test func tokenTotalsAggregatedAcrossSpans() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            model: "claude-opus-4", inputTokens: 300, outputTokens: 100, cacheReadTokens: 50))
        ctx.insert(OTLPSpan(traceId: "t2", spanId: "s2",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            model: "claude-sonnet-4", inputTokens: 700, outputTokens: 200, cacheReadTokens: 150))
        try ctx.save()

        let repo = MetricsRepository(modelContainer: container)
        let range = DateInterval(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(1))
        let (_, summary) = try await repo.computeSummary(dateRange: range, selectedModels: [])
        #expect(summary.totalInputTokens == 1000)
        #expect(summary.totalOutputTokens == 300)
        #expect(summary.totalCacheReadTokens == 200)
    }
}
