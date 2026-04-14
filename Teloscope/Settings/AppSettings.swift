// SPDX-License-Identifier: MIT
import Foundation
import Observation

@Observable
final class AppSettings {
    var port: Int
    var autoStart: Bool
    var retentionDays: Int

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        port = defaults.object(forKey: "serverPort") as? Int ?? 4318
        autoStart = defaults.bool(forKey: "autoStart")
        retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 180
    }

    func save() {
        defaults.set(port, forKey: "serverPort")
        defaults.set(autoStart, forKey: "autoStart")
        defaults.set(retentionDays, forKey: "retentionDays")
    }
}
