// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Raw metrics payload kept for reference. Parsed numeric data points are stored in MetricDataPoint.
@Model
final class ResourceMetrics {
    var receivedAt: Date
    var rawData: Data

    init(receivedAt: Date = Date(), rawData: Data) {
        self.receivedAt = receivedAt
        self.rawData = rawData
    }
}
