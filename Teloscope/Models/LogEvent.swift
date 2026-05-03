// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@Model
final class LogEvent {
    var eventName: String
    var timestamp: Date
    var sessionId: String?
    var skillName: String?
    var invocationTrigger: String?
    var skillSource: String?

    init(
        eventName: String,
        timestamp: Date,
        sessionId: String? = nil,
        skillName: String? = nil,
        invocationTrigger: String? = nil,
        skillSource: String? = nil
    ) {
        self.eventName = eventName
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.skillName = skillName
        self.invocationTrigger = invocationTrigger
        self.skillSource = skillSource
    }
}
