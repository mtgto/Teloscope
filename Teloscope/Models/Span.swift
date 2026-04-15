// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

enum AttributeValue: Codable, Equatable {
    case string(String)
    case int64(Int64)
    case double(Double)
    case bool(Bool)
    case stringArray([String])
}

enum OTLPSpanKind: Int, Codable {
    case unspecified = 0
    case `internal` = 1
    case server = 2
    case client = 3
    case producer = 4
    case consumer = 5
}

enum OTLPSpanStatus: Int, Codable {
    case unset = 0
    case ok = 1
    case error = 2
}

@Model
final class SpanAttribute {
    var key: String
    /// Stores AttributeValue as a JSON string because SwiftData does not natively support enums with associated values.
    var valueJSON: String

    init(key: String, value: AttributeValue) {
        self.key = key
        self.valueJSON = (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? ""
    }

    var value: AttributeValue? {
        guard let data = valueJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AttributeValue.self, from: data)
    }
}

@Model
final class OTLPSpan {
    var traceId: String
    var spanId: String
    var parentSpanId: String?
    var name: String
    var kindRaw: Int
    var startTime: Date
    var endTime: Date
    var statusRaw: Int
    @Relationship(deleteRule: .cascade)
    var attributes: [SpanAttribute]

    var kind: OTLPSpanKind { OTLPSpanKind(rawValue: kindRaw) ?? .unspecified }
    var status: OTLPSpanStatus { OTLPSpanStatus(rawValue: statusRaw) ?? .unset }

    init(
        traceId: String,
        spanId: String,
        parentSpanId: String? = nil,
        name: String,
        kind: OTLPSpanKind = .unspecified,
        startTime: Date,
        endTime: Date,
        status: OTLPSpanStatus = .unset,
        attributes: [SpanAttribute] = []
    ) {
        self.traceId = traceId
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.name = name
        self.kindRaw = kind.rawValue
        self.startTime = startTime
        self.endTime = endTime
        self.statusRaw = status.rawValue
        self.attributes = attributes
    }
}
