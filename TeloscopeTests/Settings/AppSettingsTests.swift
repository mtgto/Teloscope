// SPDX-License-Identifier: MIT
import Testing
import Foundation
@testable import Teloscope

struct AppSettingsTests {
    private func makeDefaults(suiteName: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func defaultValues() {
        let settings = AppSettings(defaults: makeDefaults(suiteName: "test.AppSettingsTests.defaultValues"))
        #expect(settings.port == 4318)
        #expect(settings.autoStart == false)
        #expect(settings.retentionDays == 180)
    }

    @Test func persistsValues() {
        let defaults = makeDefaults(suiteName: "test.AppSettingsTests.persistsValues")
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

    @Test func weekStartDayDefaultsToSystemCalendar() {
        let settings = AppSettings(defaults: makeDefaults(suiteName: "test.AppSettingsTests.weekStartDayDefaultsToSystemCalendar"))
        let expected = Calendar.current.firstWeekday == 1 ? 1 : 2
        #expect(settings.weekStartDay == expected)
    }

    @Test func weekStartDayPersists() {
        let defaults = makeDefaults(suiteName: "test.AppSettingsTests.weekStartDayPersists")
        let settings = AppSettings(defaults: defaults)
        settings.weekStartDay = 1
        settings.save()

        let settings2 = AppSettings(defaults: defaults)
        #expect(settings2.weekStartDay == 1)
    }
}
