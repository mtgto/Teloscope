// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class TracesListModel {
    private(set) var sessions: [SessionRow] = []
    private(set) var selectedSpans: [TraceSpanSnapshot] = []
    private(set) var isLoadingSelection = false

    private var repository: TracesRepository?
    private var isReloadingSessions = false
    private var sessionsReloadPending = false
    /// Guards against an older selection load overwriting a newer one.
    private var selectionGeneration = 0

    /// Reloads the session outline. Overlapping requests are coalesced: since
    /// `TracesRepository.loadSessions` can't be cancelled mid-flight (it's a
    /// synchronous SwiftData fetch inside an actor), the bursty ingestion
    /// notifications that arrive while Claude Code is running would otherwise queue
    /// up reloads whose results are immediately discarded. At most one extra reload
    /// runs after the in-flight one finishes.
    func reloadSessions(container: ModelContainer) {
        let repository = repository(for: container)
        sessionsReloadPending = true
        guard !isReloadingSessions else { return }
        runNextSessionsReload(repository)
    }

    private func runNextSessionsReload(_ repository: TracesRepository) {
        guard sessionsReloadPending else {
            isReloadingSessions = false
            return
        }
        sessionsReloadPending = false
        isReloadingSessions = true
        Task {
            if let loaded = try? await repository.loadSessions() {
                sessions = loaded
            }
            runNextSessionsReload(repository)
        }
    }

    func loadSelection(_ selection: TraceSelection?, container: ModelContainer) {
        let repository = repository(for: container)
        selectionGeneration += 1
        let generation = selectionGeneration

        guard let selection else {
            selectedSpans = []
            isLoadingSelection = false
            return
        }

        let traceIds: [String]
        switch selection {
        case .session(let sessionId):
            traceIds = sessions.first { $0.id == sessionId }?.traces.map(\.traceId) ?? []
        case .trace(let traceId):
            traceIds = [traceId]
        }

        selectedSpans = []
        isLoadingSelection = true
        Task {
            let loaded = (try? await repository.loadSpans(forTraceIds: traceIds)) ?? []
            guard generation == selectionGeneration else { return }
            selectedSpans = loaded
            isLoadingSelection = false
        }
    }

    private func repository(for container: ModelContainer) -> TracesRepository {
        if let repository { return repository }
        let created = TracesRepository(modelContainer: container)
        repository = created
        return created
    }
}
