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
            ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self,
            configurations: config
        )
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
