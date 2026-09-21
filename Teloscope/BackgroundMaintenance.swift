// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Owns the app-lifetime store maintenance: the one-off schema backfill and the
/// recurring retention sweep. Both run through the ingestion actor, so neither
/// touches the main thread.
///
/// Starting is idempotent because its caller is the main window's `.task`, which SwiftUI
/// re-runs whenever the window is reopened; without the guard every reopen would leave
/// another retention timer behind.
@MainActor
final class BackgroundMaintenance {
    private(set) var retentionTimer: Timer?

    func startIfNeeded(container: ModelContainer, retentionDays: Int) {
        guard retentionTimer == nil else { return }
        let service = OTLPIngestionService(modelContainer: container)
        Task {
            await service.backfillMetricTypes()
            await service.deleteOldData(retentionDays: retentionDays)
        }
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { await service.deleteOldData(retentionDays: retentionDays) }
        }
    }
}
