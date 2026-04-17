// SPDX-License-Identifier: MIT
import Testing
import SwiftData
import Foundation
@testable import Teloscope

struct SpanTests {
    @Test func spanCreation() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
            ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self,
            configurations: config
        )
        let context = ModelContext(container)

        let attr = SpanAttribute(key: "http.method", value: .string("GET"))
        let span = OTLPSpan(
            traceId: "abc123",
            spanId: "def456",
            parentSpanId: nil,
            name: "GET /api",
            kind: .server,
            startTime: Date(timeIntervalSince1970: 1000),
            endTime: Date(timeIntervalSince1970: 1001),
            status: .ok,
            attributes: [attr]
        )
        context.insert(span)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<OTLPSpan>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "GET /api")
        #expect(fetched[0].kind == .server)
        #expect(fetched[0].status == .ok)
        #expect(fetched[0].parentSpanId == nil)
        #expect(fetched[0].attributes.first?.value == .string("GET"))
    }

    @Test func attributeValueRoundTrip() throws {
        let values: [AttributeValue] = [
            .string("hello"),
            .int64(42),
            .double(3.14),
            .bool(true),
            .stringArray(["a", "b"])
        ]
        for value in values {
            let attr = SpanAttribute(key: "k", value: value)
            #expect(attr.value == value)
        }
    }
}
