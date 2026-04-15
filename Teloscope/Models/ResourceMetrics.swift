// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Metrics are stored as raw data only in the current phase. Visualization is planned for a future phase.
@Model
final class ResourceMetrics {
    var receivedAt: Date
    var rawData: Data

    init(receivedAt: Date = Date(), rawData: Data) {
        self.receivedAt = receivedAt
        self.rawData = rawData
    }
}
