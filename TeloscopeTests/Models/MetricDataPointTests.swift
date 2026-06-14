// SPDX-License-Identifier: MIT
import Testing
import Foundation
@testable import Teloscope

struct MetricDataPointTests {
    @Test func initStoresAllFields() {
        let ts = Date(timeIntervalSince1970: 1_000)
        let attr = MetricAttribute(key: "type", value: "added")
        let dp = MetricDataPoint(
            metricName: "claude_code.lines_of_code.count",
            metricUnit: "{lines}",
            timestamp: ts,
            value: 42.0,
            attributes: [attr]
        )
        #expect(dp.metricName == "claude_code.lines_of_code.count")
        #expect(dp.metricUnit == "{lines}")
        #expect(dp.timestamp == ts)
        #expect(dp.value == 42.0)
        #expect(dp.attributes.count == 1)
        #expect(dp.attributes[0].key == "type")
        #expect(dp.attributes[0].value == "added")
    }

    @Test func initWithNoAttributes() {
        let dp = MetricDataPoint(
            metricName: "claude_code.commits",
            metricUnit: "{commits}",
            timestamp: Date(),
            value: 3.0,
            attributes: []
        )
        #expect(dp.attributes.isEmpty)
    }
}
