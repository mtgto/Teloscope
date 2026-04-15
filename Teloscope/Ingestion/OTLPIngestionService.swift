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
        guard let proto = try? Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest(serializedData: data) else { return }
        for rsProto in proto.resourceSpans {
            let rs = ResourceSpans()
            rs.resourceAttributes = rsProto.resource.attributes.map {
                ResourceAttribute(key: $0.key, value: AttributeValue(anyValue: $0.value))
            }
            rs.scopeSpans = rsProto.scopeSpans.map { ssProto in
                let ss = ScopeSpans(scopeName: ssProto.scope.name, scopeVersion: ssProto.scope.version)
                ss.spans = ssProto.spans.map { sProto in
                    OTLPSpan(
                        traceId: sProto.traceID.hexString,
                        spanId: sProto.spanID.hexString,
                        parentSpanId: sProto.parentSpanID.isEmpty ? nil : sProto.parentSpanID.hexString,
                        name: sProto.name,
                        kind: OTLPSpanKind(protoKind: sProto.kind),
                        startTime: Date(unixNano: sProto.startTimeUnixNano),
                        endTime: Date(unixNano: sProto.endTimeUnixNano),
                        status: OTLPSpanStatus(protoCode: sProto.status.code),
                        attributes: sProto.attributes.map {
                            SpanAttribute(key: $0.key, value: AttributeValue(anyValue: $0.value))
                        }
                    )
                }
                return ss
            }
            modelContext.insert(rs)
        }
        try? modelContext.save()
    }

    private func ingestMetrics(_ data: Data) {
        modelContext.insert(ResourceMetrics(rawData: data))
        try? modelContext.save()
    }

    private func ingestLogs(_ data: Data) {
        modelContext.insert(ResourceLogs(rawData: data))
        try? modelContext.save()
    }

    func deleteOldData(retentionDays: Int) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
        let predicate = #Predicate<OTLPSpan> { $0.startTime < cutoff }
        try? modelContext.delete(model: OTLPSpan.self, where: predicate)
        try? modelContext.save()
    }
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
