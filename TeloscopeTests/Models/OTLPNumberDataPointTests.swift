// SPDX-License-Identifier: MIT
import Testing
import Foundation
@testable import Teloscope

struct OTLPNumberDataPointTests {
    @Test func initStoresAllFields() {
        let ts = Date(timeIntervalSince1970: 1_000)
        let dp = OTLPNumberDataPoint(
            metricName: "claude_code.lines_of_code.count",
            metricUnit: "{lines}",
            timestamp: ts,
            value: 42.0,
            attributesJSON: #"{"type":"added"}"#
        )
        #expect(dp.metricName == "claude_code.lines_of_code.count")
        #expect(dp.metricUnit == "{lines}")
        #expect(dp.timestamp == ts)
        #expect(dp.value == 42.0)
        #expect(dp.attributesJSON == #"{"type":"added"}"#)
    }
}
