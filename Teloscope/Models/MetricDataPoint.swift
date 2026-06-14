// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

// Stores a single data point from an OTLP metric. In the OTLP protocol, one Metric
// contains multiple DataPoints (each with its own timestamp, value, and attributes),
// so this model maps to the DataPoint level rather than the Metric level.
// Named MetricDataPoint instead of OTLPMetric to avoid implying a one-to-one
// correspondence with an OTLP Metric resource.
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
