// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Logs は現フェーズでは rawData 保存のみ。表示は将来フェーズ。
@Model
final class ResourceLogs {
    var receivedAt: Date
    var rawData: Data

    init(receivedAt: Date = Date(), rawData: Data) {
        self.receivedAt = receivedAt
        self.rawData = rawData
    }
}
