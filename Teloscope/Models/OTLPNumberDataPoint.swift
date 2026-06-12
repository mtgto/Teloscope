// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@Model
final class OTLPNumberDataPoint {
    var metricName: String
    var metricUnit: String
    var timestamp: Date
    var value: Double
    var attributesJSON: String

    init(
        metricName: String,
        metricUnit: String,
        timestamp: Date,
        value: Double,
        attributesJSON: String
    ) {
        self.metricName = metricName
        self.metricUnit = metricUnit
        self.timestamp = timestamp
        self.value = value
        self.attributesJSON = attributesJSON
    }
}
