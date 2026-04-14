// SPDX-License-Identifier: MIT
import Testing
@testable import Teloscope

struct AppSettingsTests {
    @Test func defaultValues() {
        let defaults = UserDefaults(suiteName: "test.AppSettingsTests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.port == 4318)
        #expect(settings.autoStart == false)
        #expect(settings.retentionDays == 180)
    }

    @Test func persistsValues() {
        let suiteName = "test.AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.port = 9999
        settings.autoStart = true
        settings.retentionDays = 30
        settings.save()

        let settings2 = AppSettings(defaults: defaults)
        #expect(settings2.port == 9999)
        #expect(settings2.autoStart == true)
        #expect(settings2.retentionDays == 30)
    }
}
