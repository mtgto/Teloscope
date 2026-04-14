// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Metrics は現フェーズでは rawData 保存のみ。表示は将来フェーズ。
@Model
final class ResourceMetrics {
    var receivedAt: Date
    var rawData: Data

    init(receivedAt: Date = Date(), rawData: Data) {
        self.receivedAt = receivedAt
        self.rawData = rawData
    }
}
