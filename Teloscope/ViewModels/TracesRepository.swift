// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@ModelActor
actor TracesRepository {
    /// Builds the session/trace outline from root spans only.
    ///
    /// Fetch cost is linear in the number of materialized objects (~35µs each with
    /// SwiftData), so reading only root spans instead of every span is what keeps this
    /// fast: on a 71k-span store that is ~5.8k objects (~0.2s) rather than ~2.5s.
    /// Per-trace span counts are deliberately not reported — they would require
    /// materializing every span again.
    func loadSessions() throws -> [SessionRow] {
        var descriptor = FetchDescriptor<OTLPSpan>(
            predicate: #Predicate { $0.parentSpanId == nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.includePendingChanges = false
        let rootSpans = try modelContext.fetch(descriptor)

        // A trace is expected to have exactly one root span. Tolerate duplicates by
        // keeping the earliest, so the trace's start time stays correct.
        var rootsByTrace: [String: (row: TraceRow, sessionId: String)] = [:]
        for span in rootSpans {
            if let existing = rootsByTrace[span.traceId], existing.row.startTime <= span.startTime {
                continue
            }
            rootsByTrace[span.traceId] = (
                row: TraceRow(traceId: span.traceId, startTime: span.startTime, rootSpanName: span.name),
                sessionId: span.sessionId ?? SessionRow.unknownSessionId
            )
        }

        let bySession = Dictionary(grouping: rootsByTrace.values, by: \.sessionId)
        return bySession
            .map { sessionId, roots in
                SessionRow(id: sessionId, traces: roots.map(\.row).sorted { $0.startTime > $1.startTime })
            }
            .sorted { $0.startTime > $1.startTime }
    }

    /// Loads every span of the given traces, oldest-first, as value types.
    func loadSpans(forTraceIds traceIds: [String]) throws -> [TraceSpanSnapshot] {
        guard !traceIds.isEmpty else { return [] }
        var descriptor = FetchDescriptor<OTLPSpan>(
            predicate: #Predicate { traceIds.contains($0.traceId) },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        descriptor.includePendingChanges = false
        return try modelContext.fetch(descriptor).map { TraceSpanSnapshot($0) }
    }
}
