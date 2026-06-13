// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@Model
final class MetricDataPoint {
    var metricName: String
    var metricUnit: String
    var timestamp: Date
    var value: Double
    @Relationship(deleteRule: .cascade) var attributes: [MetricAttribute]

    init(
        metricName: String,
        metricUnit: String,
        timestamp: Date,
        value: Double,
        attributes: [MetricAttribute] = []
    ) {
        self.metricName = metricName
        self.metricUnit = metricUnit
        self.timestamp = timestamp
        self.value = value
        self.attributes = attributes
    }
}
