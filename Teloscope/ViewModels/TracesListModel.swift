// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class TracesListModel {
    private(set) var sessions: [SessionRow] = []
    private(set) var isLoadingSessions = false
    private(set) var detailState: TraceDetailState = .empty

    // Two repositories, so a selection never waits behind a session reload. A
    // @ModelActor serializes its calls, and reloading the session outline takes
    // ~270ms on a large store; with ingestion notifications arriving continuously
    // while Claude Code runs, a shared actor left selections queued for ~0.3-0.6s.
    // On their own actor they stay at ~10ms.
    private var sessionRepository: TracesRepository?
    private var spanRepository: TracesRepository?

    /// Ingestion posts a notification per OTLP request, and a reload takes ~270ms on a
    /// large store. Reloading on every notification keeps the store busy back-to-back,
    /// which is what a selection then has to wait behind. The trace list does not need
    /// to be that fresh, so reloads are spaced out.
    private let minimumReloadInterval: TimeInterval = 2

    private var isReloadingSessions = false
    private var sessionsReloadPending = false
    private var lastReloadFinishedAt: Date?
    /// Guards against an older selection load overwriting a newer one.
    private var selectionGeneration = 0

    /// Reloads the session outline. Overlapping requests are coalesced: since
    /// `TracesRepository.loadSessions` can't be cancelled mid-flight (it's a
    /// synchronous SwiftData fetch inside an actor), the bursty ingestion
    /// notifications that arrive while Claude Code is running would otherwise queue
    /// up reloads whose results are immediately discarded. At most one extra reload
    /// runs after the in-flight one finishes.
    func reloadSessions(container: ModelContainer) {
        let repository = sessionRepository(for: container)
        sessionsReloadPending = true
        guard !isReloadingSessions else { return }
        isLoadingSessions = true
        runNextSessionsReload(repository)
    }

    private func runNextSessionsReload(_ repository: TracesRepository) {
        guard sessionsReloadPending else {
            isReloadingSessions = false
            isLoadingSessions = false
            return
        }
        sessionsReloadPending = false
        isReloadingSessions = true
        Task {
            if let last = lastReloadFinishedAt {
                let remaining = minimumReloadInterval - Date().timeIntervalSince(last)
                if remaining > 0 {
                    try? await Task.sleep(for: .seconds(remaining))
                }
            }
            if let loaded = try? await repository.loadSessions() {
                sessions = loaded
            }
            lastReloadFinishedAt = Date()
            runNextSessionsReload(repository)
        }
    }

    /// Loads the spans behind a selection. `detailState` moves to `.loading`
    /// before this returns, so the view always has a loading state to render.
    func loadSelection(_ selection: TraceSelection?, container: ModelContainer) {
        let repository = spanRepository(for: container)
        selectionGeneration += 1
        let generation = selectionGeneration

        guard let selection else {
            detailState = .empty
            return
        }

        let traceIds: [String]
        switch selection {
        case .session(let sessionId):
            traceIds = sessions.first { $0.id == sessionId }?.traces.map(\.traceId) ?? []
        case .trace(let traceId):
            traceIds = [traceId]
        }

        detailState = .loading(selection)
        Task {
            let loaded = (try? await repository.loadSpans(forTraceIds: traceIds)) ?? []
            guard generation == selectionGeneration else { return }
            detailState = .loaded(selection, loaded)
        }
    }

    private func sessionRepository(for container: ModelContainer) -> TracesRepository {
        if let sessionRepository { return sessionRepository }
        let created = TracesRepository(modelContainer: container)
        sessionRepository = created
        return created
    }

    private func spanRepository(for container: ModelContainer) -> TracesRepository {
        if let spanRepository { return spanRepository }
        let created = TracesRepository(modelContainer: container)
        spanRepository = created
        return created
    }
}
