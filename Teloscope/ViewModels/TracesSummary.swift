// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// One trace in the session list. Built from the trace's root span alone, so the
/// list can be assembled without materializing every span in the store.
struct TraceRow: Identifiable, Hashable, Sendable {
    let traceId: String
    let startTime: Date
    let rootSpanName: String

    var id: String { traceId }
}

/// A Claude Code session: the traces that share one `session.id`.
struct SessionRow: Identifiable, Hashable, Sendable {
    /// Sentinel used for traces whose root span carries no `session.id`.
    static let unknownSessionId = "unknown"

    let id: String
    /// Sorted newest-first.
    let traces: [TraceRow]

    var startTime: Date { traces.first?.startTime ?? .distantPast }
    var traceCount: Int { traces.count }
}

enum TraceSelection: Hashable {
    case session(String)
    case trace(String)
}

/// What the detail panel should show. Kept as one value so the panel can never
/// render a selection's content before that selection's spans have loaded —
/// which would flash an empty Gantt chart instead of the loading indicator.
enum TraceDetailState {
    case empty
    case loading(TraceSelection)
    case loaded(TraceSelection, [TraceSpanSnapshot])
}

/// Value-type view of an `OTLPSpan`, safe to hand to the main actor.
///
/// Carries only the typed columns the Gantt chart and session summary need. The
/// `attributes` relationship is deliberately left out — faulting it for a whole
/// session was an N+1 query storm, and only the span detail popover ever needs
/// it, which looks the span up on demand via `persistentID`.
struct TraceSpanSnapshot: Identifiable, Hashable, Sendable {
    let spanId: String
    let traceId: String
    let parentSpanId: String?
    let name: String
    let startTime: Date
    let endTime: Date
    let kind: OTLPSpanKind
    let status: OTLPSpanStatus
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheReadTokens: Int64
    let decision: String?
    let toolName: String?
    /// Identifies the backing span so the detail popover can fetch its attributes.
    /// `nil` for snapshots built outside a model container (previews, tests).
    let persistentID: PersistentIdentifier?

    var id: String { spanId }

    init(
        spanId: String,
        traceId: String,
        parentSpanId: String? = nil,
        name: String,
        startTime: Date,
        endTime: Date,
        kind: OTLPSpanKind = .unspecified,
        status: OTLPSpanStatus = .unset,
        inputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        cacheReadTokens: Int64 = 0,
        decision: String? = nil,
        toolName: String? = nil,
        persistentID: PersistentIdentifier? = nil
    ) {
        self.spanId = spanId
        self.traceId = traceId
        self.parentSpanId = parentSpanId
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.kind = kind
        self.status = status
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.decision = decision
        self.toolName = toolName
        self.persistentID = persistentID
    }

    init(_ span: OTLPSpan) {
        self.init(
            spanId: span.spanId,
            traceId: span.traceId,
            parentSpanId: span.parentSpanId,
            name: span.name,
            startTime: span.startTime,
            endTime: span.endTime,
            kind: span.kind,
            status: span.status,
            inputTokens: span.inputTokens ?? 0,
            outputTokens: span.outputTokens ?? 0,
            cacheReadTokens: span.cacheReadTokens ?? 0,
            decision: span.decision,
            toolName: span.toolName,
            persistentID: span.persistentModelID
        )
    }
}
