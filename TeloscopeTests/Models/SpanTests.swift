// SPDX-License-Identifier: MIT
import Testing
@testable import Teloscope

struct SpanTests {
    /// `SpanAttribute` stores its value as a JSON string because SwiftData cannot persist
    /// enums with associated values, so every case has to survive the encode/decode pair.
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
