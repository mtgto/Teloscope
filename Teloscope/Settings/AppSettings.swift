// SPDX-License-Identifier: MIT
import Foundation
import Observation

@Observable
final class AppSettings {
    var port: Int
    var autoStart: Bool
    var retentionDays: Int
    var weekStartDay: Int

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["weekStartDay": Calendar.current.firstWeekday])
        port = defaults.object(forKey: "serverPort") as? Int ?? 4318
        autoStart = defaults.bool(forKey: "autoStart")
        retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 180
        weekStartDay = defaults.object(forKey: "weekStartDay") as? Int ?? Calendar.current.firstWeekday
    }

    func save() {
        defaults.set(port, forKey: "serverPort")
        defaults.set(autoStart, forKey: "autoStart")
        defaults.set(retentionDays, forKey: "retentionDays")
        defaults.set(weekStartDay, forKey: "weekStartDay")
    }
}
