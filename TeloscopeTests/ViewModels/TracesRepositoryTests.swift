// SPDX-License-Identifier: MIT
import Testing
import SwiftData
import Foundation
@testable import Teloscope

struct TracesRepositoryTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
                 ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self, LogEvent.self,
                 MetricDataPoint.self, MetricAttribute.self,
            configurations: config
        )
    }

    // MARK: - Session list

    @Test func sessionsGroupTracesByRootSpanSessionId() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "r1", name: "root-1",
                            startTime: now, endTime: now.addingTimeInterval(1), sessionId: "A"))
        ctx.insert(OTLPSpan(traceId: "t2", spanId: "r2", name: "root-2",
                            startTime: now.addingTimeInterval(10), endTime: now.addingTimeInterval(11),
                            sessionId: "A"))
        ctx.insert(OTLPSpan(traceId: "t3", spanId: "r3", name: "root-3",
                            startTime: now.addingTimeInterval(20), endTime: now.addingTimeInterval(21),
                            sessionId: "B"))
        try ctx.save()

        let sessions = try await TracesRepository(modelContainer: container).loadSessions()

        #expect(sessions.count == 2)
        let a = try #require(sessions.first { $0.id == "A" })
        #expect(a.traceCount == 2)
        #expect(Set(a.traces.map(\.traceId)) == ["t1", "t2"])
        let b = try #require(sessions.first { $0.id == "B" })
        #expect(b.traces.map(\.traceId) == ["t3"])
    }

    @Test func rootSpanWithoutSessionIdIsGroupedAsUnknown() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "r1", name: "root-1",
                            startTime: now, endTime: now.addingTimeInterval(1)))
        try ctx.save()

        let sessions = try await TracesRepository(modelContainer: container).loadSessions()

        #expect(sessions.map(\.id) == [SessionRow.unknownSessionId])
    }

    @Test func sessionsAndTracesAreSortedNewestFirst() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "old", spanId: "r1", name: "root",
                            startTime: now, endTime: now.addingTimeInterval(1), sessionId: "A"))
        ctx.insert(OTLPSpan(traceId: "new", spanId: "r2", name: "root",
                            startTime: now.addingTimeInterval(100), endTime: now.addingTimeInterval(101),
                            sessionId: "A"))
        ctx.insert(OTLPSpan(traceId: "newest", spanId: "r3", name: "root",
                            startTime: now.addingTimeInterval(200), endTime: now.addingTimeInterval(201),
                            sessionId: "B"))
        try ctx.save()

        let sessions = try await TracesRepository(modelContainer: container).loadSessions()

        #expect(sessions.map(\.id) == ["B", "A"])
        #expect(sessions[1].traces.map(\.traceId) == ["new", "old"])
    }

    @Test func traceRowUsesRootSpanNameAndStartTime() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "r1", name: "claude_code.interaction",
                            startTime: now, endTime: now.addingTimeInterval(5), sessionId: "A"))
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "c1", parentSpanId: "r1", name: "claude_code.tool",
                            startTime: now.addingTimeInterval(1), endTime: now.addingTimeInterval(2),
                            sessionId: "A"))
        try ctx.save()

        let sessions = try await TracesRepository(modelContainer: container).loadSessions()

        let trace = try #require(sessions.first?.traces.first)
        #expect(trace.rootSpanName == "claude_code.interaction")
        #expect(trace.startTime == now)
    }

    @Test func childSpansDoNotProduceExtraTraceRows() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "r1", name: "root",
                            startTime: now, endTime: now.addingTimeInterval(1), sessionId: "A"))
        for i in 0..<5 {
            ctx.insert(OTLPSpan(traceId: "t1", spanId: "c\(i)", parentSpanId: "r1", name: "child",
                                startTime: now, endTime: now.addingTimeInterval(1), sessionId: "A"))
        }
        try ctx.save()

        let sessions = try await TracesRepository(modelContainer: container).loadSessions()

        #expect(sessions.count == 1)
        #expect(sessions[0].traceCount == 1)
    }

    @Test func duplicateRootSpansForSameTraceProduceOneRowWithEarliestStart() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "r1", name: "first",
                            startTime: now, endTime: now.addingTimeInterval(1), sessionId: "A"))
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "r2", name: "second",
                            startTime: now.addingTimeInterval(50), endTime: now.addingTimeInterval(51),
                            sessionId: "A"))
        try ctx.save()

        let sessions = try await TracesRepository(modelContainer: container).loadSessions()

        #expect(sessions.count == 1)
        #expect(sessions[0].traceCount == 1)
        #expect(sessions[0].traces[0].startTime == now)
    }

    @Test func emptyStoreProducesNoSessions() async throws {
        let container = try makeContainer()
        let sessions = try await TracesRepository(modelContainer: container).loadSessions()
        #expect(sessions.isEmpty)
    }

    // MARK: - Span loading for a selection

    @Test func loadSpansReturnsRequestedTracesSortedByStartTime() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "late", name: "late",
                            startTime: now.addingTimeInterval(10), endTime: now.addingTimeInterval(11)))
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "early", name: "early",
                            startTime: now, endTime: now.addingTimeInterval(1)))
        ctx.insert(OTLPSpan(traceId: "other", spanId: "excluded", name: "excluded",
                            startTime: now, endTime: now.addingTimeInterval(1)))
        try ctx.save()

        let spans = try await TracesRepository(modelContainer: container).loadSpans(forTraceIds: ["t1"])

        #expect(spans.map(\.spanId) == ["early", "late"])
    }

    @Test func loadSpansCoversEveryTraceOfASession() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        for (traceId, spanId) in [("t1", "s1"), ("t2", "s2"), ("t3", "s3")] {
            ctx.insert(OTLPSpan(traceId: traceId, spanId: spanId, name: "span",
                                startTime: now, endTime: now.addingTimeInterval(1), sessionId: "A"))
        }
        try ctx.save()

        let spans = try await TracesRepository(modelContainer: container).loadSpans(forTraceIds: ["t1", "t2", "t3"])

        #expect(Set(spans.map(\.spanId)) == ["s1", "s2", "s3"])
    }

    @Test func loadSpansWithNoTraceIdsReturnsEmpty() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1", name: "span",
                            startTime: now, endTime: now.addingTimeInterval(1)))
        try ctx.save()

        let spans = try await TracesRepository(modelContainer: container).loadSpans(forTraceIds: [])

        #expect(spans.isEmpty)
    }

    @Test func loadSpansCarriesTypedColumnsNeededBySummaryAndChart() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1", parentSpanId: "root",
                            name: "claude_code.llm_request",
                            startTime: now, endTime: now.addingTimeInterval(1), status: .error,
                            sessionId: "A", inputTokens: 100, outputTokens: 20, cacheReadTokens: 5,
                            decision: "accept", toolName: "Bash"))
        try ctx.save()

        let spans = try await TracesRepository(modelContainer: container).loadSpans(forTraceIds: ["t1"])

        let span = try #require(spans.first)
        #expect(span.parentSpanId == "root")
        #expect(span.status == .error)
        #expect(span.inputTokens == 100)
        #expect(span.outputTokens == 20)
        #expect(span.cacheReadTokens == 5)
        #expect(span.decision == "accept")
        #expect(span.toolName == "Bash")
        #expect(span.persistentID != nil)
    }
}
