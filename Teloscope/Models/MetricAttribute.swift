// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@Model
final class MetricAttribute {
    var key: String
    var value: String

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}
