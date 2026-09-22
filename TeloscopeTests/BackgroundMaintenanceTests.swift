// SPDX-License-Identifier: MIT
import Testing
import SwiftData
import Foundation
@testable import Teloscope

@MainActor
struct BackgroundMaintenanceTests {
    @Test func startIfNeededSchedulesOneTimer() throws {
        let container = try makeTestModelContainer()
        let maintenance = BackgroundMaintenance()

        maintenance.startIfNeeded(container: container, retentionDays: 180)

        #expect(maintenance.retentionTimer != nil)
    }

    /// The window's `.task` re-runs every time the window is reopened, so a second call
    /// must keep the timer it already has rather than stacking another one.
    @Test func startIfNeededKeepsTheExistingTimer() throws {
        let container = try makeTestModelContainer()
        let maintenance = BackgroundMaintenance()

        maintenance.startIfNeeded(container: container, retentionDays: 180)
        let first = try #require(maintenance.retentionTimer)
        maintenance.startIfNeeded(container: container, retentionDays: 180)

        #expect(maintenance.retentionTimer === first)
    }
}
