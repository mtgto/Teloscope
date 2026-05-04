// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import SwiftProtobuf

final class OTLPIngestionService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func ingest(_ request: OTLPRequest) {
        switch request {
        case .traces(let data): ingestTraces(data)
        case .metrics(let data): ingestMetrics(data)
        case .logs(let data): ingestLogs(data)
        }
    }

    private func ingestTraces(_ data: Data) {
        guard let proto = try? Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest(serializedBytes: data) else { return }
        for rsProto in proto.resourceSpans {
            let rs = ResourceSpans(rawData: data)
            rs.resourceAttributes = rsProto.resource.attributes.map {
                ResourceAttribute(key: $0.key, value: AttributeValue(anyValue: $0.value))
            }
            rs.scopeSpans = rsProto.scopeSpans.map { ssProto in
                let ss = ScopeSpans(scopeName: ssProto.scope.name, scopeVersion: ssProto.scope.version)
                ss.spans = ssProto.spans.map { sProto in
                    // Build a temporary dictionary for O(1) attribute lookup during construction.
                    let attrs = Dictionary(
                        sProto.attributes.map { ($0.key, AttributeValue(anyValue: $0.value)) },
                        uniquingKeysWith: { first, _ in first }
                    )
                    return OTLPSpan(
                        traceId: sProto.traceID.hexString,
                        spanId: sProto.spanID.hexString,
                        parentSpanId: sProto.parentSpanID.isEmpty ? nil : sProto.parentSpanID.hexString,
                        name: sProto.name,
                        kind: OTLPSpanKind(protoKind: sProto.kind),
                        startTime: Date(unixNano: sProto.startTimeUnixNano),
                        endTime: Date(unixNano: sProto.endTimeUnixNano),
                        status: OTLPSpanStatus(protoCode: sProto.status.code),
                        attributes: attrs.map { SpanAttribute(key: $0.key, value: $0.value) },
                        sessionId: attrs["session.id"]?.stringValue,
                        model: attrs["model"]?.stringValue,
                        inputTokens: attrs["input_tokens"]?.int64Value,
                        outputTokens: attrs["output_tokens"]?.int64Value,
                        cacheReadTokens: attrs["cache_read_tokens"]?.int64Value,
                        decision: attrs["decision"]?.stringValue,
                        toolName: attrs["tool_name"]?.stringValue
                    )
                }
                return ss
            }
            modelContext.insert(rs)
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .otlpSpansIngested, object: nil)
    }

    private func ingestMetrics(_ data: Data) {
        modelContext.insert(ResourceMetrics(rawData: data))
        try? modelContext.save()
    }

    private func ingestLogs(_ data: Data) {
        guard let proto = try? Opentelemetry_Proto_Collector_Logs_V1_ExportLogsServiceRequest(
            serializedBytes: data
        ) else { return }
        modelContext.insert(ResourceLogs(rawData: data))
        for rlProto in proto.resourceLogs {
            for slProto in rlProto.scopeLogs {
                for lrProto in slProto.logRecords {
                    let attrs = Dictionary(
                        lrProto.attributes.map { ($0.key, AttributeValue(anyValue: $0.value)) },
                        uniquingKeysWith: { first, _ in first }
                    )
                    let eventName = attrs["event.name"]?.stringValue
                    let nano = lrProto.timeUnixNano > 0
                        ? lrProto.timeUnixNano
                        : lrProto.observedTimeUnixNano
                    if eventName == "skill_activated" {
                        modelContext.insert(LogEvent(
                            eventName: "skill_activated",
                            timestamp: Date(unixNano: nano),
                            sessionId: attrs["session.id"]?.stringValue,
                            skillName: attrs["skill.name"]?.stringValue,
                            invocationTrigger: attrs["invocation_trigger"]?.stringValue,
                            skillSource: attrs["skill.source"]?.stringValue
                        ))
                    } else if eventName == "user_prompt",
                              let commandName = attrs["command_name"]?.stringValue,
                              !commandName.isEmpty {
                        modelContext.insert(LogEvent(
                            eventName: "user_prompt",
                            timestamp: Date(unixNano: nano),
                            sessionId: attrs["session.id"]?.stringValue,
                            skillName: commandName,
                            invocationTrigger: "user-slash",
                            skillSource: attrs["command_source"]?.stringValue
                        ))
                    }
                }
            }
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .otlpLogsIngested, object: nil)
    }

    func backfillTypedColumns() {
        let descriptor = FetchDescriptor<OTLPSpan>(
            predicate: #Predicate { $0.toolName == nil }
        )
        guard let spans = try? modelContext.fetch(descriptor) else { return }
        var changed = false
        for span in spans where span.name == "claude_code.tool" {
            if let attr = span.attributes.first(where: { $0.key == "tool_name" }),
               let toolName = attr.value?.stringValue {
                span.toolName = toolName
                changed = true
            }
        }
        if changed { try? modelContext.save() }
    }

    func deleteOldData(retentionDays: Int) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
        let predicate = #Predicate<OTLPSpan> { $0.startTime < cutoff }
        try? modelContext.delete(model: OTLPSpan.self, where: predicate)
        try? modelContext.save()
        NotificationCenter.default.post(name: .otlpSpansIngested, object: nil)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let otlpSpansIngested = Notification.Name("com.teloscope.otlpSpansIngested")
    static let otlpLogsIngested = Notification.Name("com.teloscope.otlpLogsIngested")
}

// MARK: - Private helpers

private extension Data {
    // Encodes each byte as two lowercase hex characters.
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

private extension Date {
    // Converts OpenTelemetry Unix nanosecond timestamp to Date.
    init(unixNano: UInt64) {
        self.init(timeIntervalSince1970: Double(unixNano) / 1_000_000_000)
    }
}

private extension AttributeValue {
    init(anyValue: Opentelemetry_Proto_Common_V1_AnyValue) {
        switch anyValue.value {
        case .stringValue(let s): self = .string(s)
        case .intValue(let i): self = .int64(i)
        case .doubleValue(let d): self = .double(d)
        case .boolValue(let b): self = .bool(b)
        case .arrayValue(let arr):
            let strings = arr.values.compactMap { v -> String? in
                if case .stringValue(let s) = v.value { return s }
                return nil
            }
            self = .stringArray(strings)
        default: self = .string("")
        }
    }
}

private extension OTLPSpanKind {
    init(protoKind: Opentelemetry_Proto_Trace_V1_Span.SpanKind) {
        switch protoKind {
        case .internal: self = .internal
        case .server: self = .server
        case .client: self = .client
        case .producer: self = .producer
        case .consumer: self = .consumer
        default: self = .unspecified
        }
    }
}

private extension OTLPSpanStatus {
    init(protoCode: Opentelemetry_Proto_Trace_V1_Status.StatusCode) {
        switch protoCode {
        case .ok: self = .ok
        case .error: self = .error
        default: self = .unset
        }
    }
}
