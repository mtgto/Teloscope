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
    // The compound index serves the summary's (metricName, timestamp) predicate;
    // the plain timestamp index serves retention deletes.
    #Index<MetricDataPoint>([\.timestamp], [\.metricName, \.timestamp])

    var metricName: String
    var metricUnit: String
    var timestamp: Date
    var value: Double

    /// Typed column mirroring the OTLP `type` attribute, following the same pattern as
    /// OTLPSpan's typed columns. Summaries read this instead of walking `attributes`,
    /// which would fault in one MetricAttribute per data point.
    var type: String?

    @Relationship(deleteRule: .cascade) var attributes: [MetricAttribute]

    init(
        metricName: String,
        metricUnit: String,
        timestamp: Date,
        value: Double,
        type: String? = nil,
        attributes: [MetricAttribute] = []
    ) {
        self.metricName = metricName
        self.metricUnit = metricUnit
        self.timestamp = timestamp
        self.value = value
        self.type = type
        self.attributes = attributes
    }
}
