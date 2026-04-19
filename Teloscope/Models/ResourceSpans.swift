// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@Model
final class ResourceAttribute {
    var key: String
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
final class ResourceSpans {
    var receivedAt: Date
    var rawData: Data?
    @Relationship(deleteRule: .cascade)
    var resourceAttributes: [ResourceAttribute]
    @Relationship(deleteRule: .cascade)
    var scopeSpans: [ScopeSpans]

    init(receivedAt: Date = Date(), rawData: Data? = nil, resourceAttributes: [ResourceAttribute] = [], scopeSpans: [ScopeSpans] = []) {
        self.receivedAt = receivedAt
        self.rawData = rawData
        self.resourceAttributes = resourceAttributes
        self.scopeSpans = scopeSpans
    }
}
