// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Logs are stored as raw data only in the current phase. Visualization is planned for a future phase.
@Model
final class ResourceLogs {
    var receivedAt: Date
    var rawData: Data

    init(receivedAt: Date = Date(), rawData: Data) {
        self.receivedAt = receivedAt
        self.rawData = rawData
    }
}
