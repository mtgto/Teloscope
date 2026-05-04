// SPDX-License-Identifier: MIT
import Testing
import SwiftData
import SwiftProtobuf
import Foundation
@testable import Teloscope

struct OTLPIngestionServiceTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
            ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self, LogEvent.self,
            configurations: config
        )
    }

    @Test func logEventCanBeInserted() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let event = LogEvent(
            eventName: "skill_activated",
            timestamp: Date(),
            sessionId: "sess-1",
            skillName: "superpowers:brainstorming",
            invocationTrigger: "claude-proactive",
            skillSource: "userSettings"
        )
        ctx.insert(event)
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<LogEvent>())
        #expect(fetched.count == 1)
        #expect(fetched[0].skillName == "superpowers:brainstorming")
    }

    @Test func ingestsSpanFromTracesRequest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = OTLPIngestionService(modelContext: context)

        var spanProto = Opentelemetry_Proto_Trace_V1_Span()
        spanProto.traceID = Data(repeating: 0xAB, count: 16)
        spanProto.spanID = Data(repeating: 0xCD, count: 8)
        spanProto.name = "test-span"
        spanProto.startTimeUnixNano = 1_000_000_000
        spanProto.endTimeUnixNano = 2_000_000_000
        spanProto.kind = .server
        spanProto.status.code = .ok

        var attrProto = Opentelemetry_Proto_Common_V1_KeyValue()
        attrProto.key = "http.method"
        attrProto.value.stringValue = "GET"
        spanProto.attributes = [attrProto]

        var scopeSpansProto = Opentelemetry_Proto_Trace_V1_ScopeSpans()
        scopeSpansProto.scope.name = "claude-code"
        scopeSpansProto.spans = [spanProto]

        var resourceSpansProto = Opentelemetry_Proto_Trace_V1_ResourceSpans()
        resourceSpansProto.scopeSpans = [scopeSpansProto]

        var request = Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest()
        request.resourceSpans = [resourceSpansProto]
        let data = try request.serializedData()

        service.ingest(.traces(data))

        let spans = try context.fetch(FetchDescriptor<OTLPSpan>())
        #expect(spans.count == 1)
        #expect(spans[0].name == "test-span")
        #expect(spans[0].kind == .server)
        #expect(spans[0].status == .ok)
        #expect(spans[0].traceId == String(repeating: "ab", count: 16))
        #expect(spans[0].attributes.first?.value == .string("GET"))
    }

    @Test func ingestPopulatesTypedColumnsForClaudeCodeSpan() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = OTLPIngestionService(modelContext: context)

        var spanProto = Opentelemetry_Proto_Trace_V1_Span()
        spanProto.traceID = Data(repeating: 0x01, count: 16)
        spanProto.spanID = Data(repeating: 0x02, count: 8)
        spanProto.name = "claude_code.llm_request"
        spanProto.startTimeUnixNano = 1_000_000_000
        spanProto.endTimeUnixNano = 2_000_000_000

        func kv(_ key: String, string value: String) -> Opentelemetry_Proto_Common_V1_KeyValue {
            var kv = Opentelemetry_Proto_Common_V1_KeyValue()
            kv.key = key; kv.value.stringValue = value; return kv
        }
        func kv(_ key: String, int value: Int64) -> Opentelemetry_Proto_Common_V1_KeyValue {
            var kv = Opentelemetry_Proto_Common_V1_KeyValue()
            kv.key = key; kv.value.intValue = value; return kv
        }
        spanProto.attributes = [
            kv("session.id",          string: "sess-abc"),
            kv("model",               string: "claude-opus-4"),
            kv("input_tokens",        int:    1000),
            kv("output_tokens",       int:    500),
            kv("cache_read_tokens",   int:    200),
        ]

        var scopeSpans = Opentelemetry_Proto_Trace_V1_ScopeSpans()
        scopeSpans.spans = [spanProto]
        var resourceSpans = Opentelemetry_Proto_Trace_V1_ResourceSpans()
        resourceSpans.scopeSpans = [scopeSpans]
        var request = Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest()
        request.resourceSpans = [resourceSpans]

        service.ingest(.traces(try request.serializedData()))

        let spans = try context.fetch(FetchDescriptor<OTLPSpan>())
        #expect(spans.count == 1)
        let span = spans[0]
        #expect(span.sessionId == "sess-abc")
        #expect(span.model == "claude-opus-4")
        #expect(span.inputTokens == 1000)
        #expect(span.outputTokens == 500)
        #expect(span.cacheReadTokens == 200)
    }

    @Test func ingestPopulatesDecisionForToolSpan() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = OTLPIngestionService(modelContext: context)

        var spanProto = Opentelemetry_Proto_Trace_V1_Span()
        spanProto.traceID = Data(repeating: 0x01, count: 16)
        spanProto.spanID = Data(repeating: 0x02, count: 8)
        spanProto.name = "claude_code.tool.blocked_on_user"
        spanProto.startTimeUnixNano = 1_000_000_000
        spanProto.endTimeUnixNano = 2_000_000_000

        var decisionAttr = Opentelemetry_Proto_Common_V1_KeyValue()
        decisionAttr.key = "decision"
        decisionAttr.value.stringValue = "accept"
        spanProto.attributes = [decisionAttr]

        var scopeSpans = Opentelemetry_Proto_Trace_V1_ScopeSpans()
        scopeSpans.spans = [spanProto]
        var resourceSpans = Opentelemetry_Proto_Trace_V1_ResourceSpans()
        resourceSpans.scopeSpans = [scopeSpans]
        var request = Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest()
        request.resourceSpans = [resourceSpans]

        service.ingest(.traces(try request.serializedData()))

        let spans = try context.fetch(FetchDescriptor<OTLPSpan>())
        #expect(spans[0].decision == "accept")
    }

    // MARK: - backfillTypedColumns

    @Test func backfillSetsToolNameFromAttribute() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let span = OTLPSpan(
            traceId: "t", spanId: "s-bf1",
            name: "claude_code.tool",
            startTime: .now, endTime: .now
        )
        span.attributes = [SpanAttribute(key: "tool_name", value: .string("Bash"))]
        context.insert(span)
        try context.save()

        OTLPIngestionService(modelContext: context).backfillTypedColumns()

        let fetched = try context.fetch(FetchDescriptor<OTLPSpan>())
        #expect(fetched.first?.toolName == "Bash")
    }

    @Test func backfillIgnoresSpansWithToolNameAlreadySet() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let span = OTLPSpan(
            traceId: "t", spanId: "s-bf2",
            name: "claude_code.tool",
            startTime: .now, endTime: .now,
            toolName: "Read"
        )
        span.attributes = [SpanAttribute(key: "tool_name", value: .string("Bash"))]
        context.insert(span)
        try context.save()

        OTLPIngestionService(modelContext: context).backfillTypedColumns()

        let fetched = try context.fetch(FetchDescriptor<OTLPSpan>())
        #expect(fetched.first?.toolName == "Read")
    }

    @Test func backfillIgnoresNonToolSpans() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let span = OTLPSpan(
            traceId: "t", spanId: "s-bf3",
            name: "claude_code.llm_request",
            startTime: .now, endTime: .now
        )
        span.attributes = [SpanAttribute(key: "tool_name", value: .string("Bash"))]
        context.insert(span)
        try context.save()

        OTLPIngestionService(modelContext: context).backfillTypedColumns()

        let fetched = try context.fetch(FetchDescriptor<OTLPSpan>())
        #expect(fetched.first?.toolName == nil)
    }

    @Test func backfillSkipsToolSpanWithNoAttribute() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let span = OTLPSpan(
            traceId: "t", spanId: "s-bf4",
            name: "claude_code.tool",
            startTime: .now, endTime: .now
        )
        context.insert(span)
        try context.save()

        OTLPIngestionService(modelContext: context).backfillTypedColumns()

        let fetched = try context.fetch(FetchDescriptor<OTLPSpan>())
        #expect(fetched.first?.toolName == nil)
    }

    // MARK: - Log ingestion helpers

    private func makeLogRequest(
        eventName: String,
        sessionId: String? = nil,
        skillName: String? = nil,
        invocationTrigger: String? = nil,
        skillSource: String? = nil,
        timeUnixNano: UInt64 = 1_000_000_000
    ) throws -> Data {
        func kv(_ key: String, _ value: String) -> Opentelemetry_Proto_Common_V1_KeyValue {
            var kv = Opentelemetry_Proto_Common_V1_KeyValue()
            kv.key = key; kv.value.stringValue = value; return kv
        }
        var logRecord = Opentelemetry_Proto_Logs_V1_LogRecord()
        logRecord.timeUnixNano = timeUnixNano
        var attrs = [kv("event.name", eventName)]
        if let v = sessionId         { attrs.append(kv("session.id", v)) }
        if let v = skillName         { attrs.append(kv("skill.name", v)) }
        if let v = invocationTrigger { attrs.append(kv("invocation_trigger", v)) }
        if let v = skillSource       { attrs.append(kv("skill.source", v)) }
        logRecord.attributes = attrs

        var scopeLogs = Opentelemetry_Proto_Logs_V1_ScopeLogs()
        scopeLogs.logRecords = [logRecord]
        var resourceLogs = Opentelemetry_Proto_Logs_V1_ResourceLogs()
        resourceLogs.scopeLogs = [scopeLogs]
        var request = Opentelemetry_Proto_Collector_Logs_V1_ExportLogsServiceRequest()
        request.resourceLogs = [resourceLogs]
        return try request.serializedData()
    }

    @Test func ingestsSkillActivatedLogEvent() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let service = OTLPIngestionService(modelContext: ctx)

        let data = try makeLogRequest(
            eventName: "skill_activated",
            sessionId: "sess-abc",
            skillName: "superpowers:brainstorming",
            invocationTrigger: "claude-proactive",
            skillSource: "userSettings"
        )
        service.ingest(.logs(data))

        let events = try ctx.fetch(FetchDescriptor<LogEvent>())
        #expect(events.count == 1)
        #expect(events[0].eventName == "skill_activated")
        #expect(events[0].sessionId == "sess-abc")
        #expect(events[0].skillName == "superpowers:brainstorming")
        #expect(events[0].invocationTrigger == "claude-proactive")
        #expect(events[0].skillSource == "userSettings")
    }

    @Test func ignoresNonSkillActivatedLogEvents() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let service = OTLPIngestionService(modelContext: ctx)

        let data = try makeLogRequest(eventName: "api_request")
        service.ingest(.logs(data))

        let events = try ctx.fetch(FetchDescriptor<LogEvent>())
        #expect(events.isEmpty)
    }

    @Test func ingestLogsPostsOtlpLogsIngestedNotification() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let service = OTLPIngestionService(modelContext: ctx)

        var notified = false
        let token = NotificationCenter.default.addObserver(
            forName: .otlpLogsIngested, object: nil, queue: .main
        ) { _ in notified = true }
        defer { NotificationCenter.default.removeObserver(token) }

        let data = try makeLogRequest(eventName: "skill_activated")
        service.ingest(.logs(data))
        #expect(notified)
    }

    @Test func deletesSpansOlderThanRetentionDays() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = OTLPIngestionService(modelContext: context)

        let old = OTLPSpan(
            traceId: "old", spanId: "s1",
            name: "old-span",
            startTime: Date(timeIntervalSinceNow: -200 * 86400),
            endTime: Date(timeIntervalSinceNow: -200 * 86400 + 1)
        )
        let recent = OTLPSpan(
            traceId: "recent", spanId: "s2",
            name: "recent-span",
            startTime: Date(timeIntervalSinceNow: -10 * 86400),
            endTime: Date(timeIntervalSinceNow: -10 * 86400 + 1)
        )
        context.insert(old)
        context.insert(recent)
        try context.save()

        service.deleteOldData(retentionDays: 180)

        let spans = try context.fetch(FetchDescriptor<OTLPSpan>())
        #expect(spans.count == 1)
        #expect(spans[0].name == "recent-span")
    }
}
