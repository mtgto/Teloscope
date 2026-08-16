// SPDX-License-Identifier: MIT
import Testing
import SwiftData
import Foundation
@testable import Teloscope

@MainActor
struct TracesListModelTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
                 ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self, LogEvent.self,
                 MetricDataPoint.self, MetricAttribute.self,
            configurations: config
        )
    }

    private func seed(_ container: ModelContainer) throws {
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "r1", name: "root",
                            startTime: now, endTime: now.addingTimeInterval(1), sessionId: "A"))
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "c1", parentSpanId: "r1", name: "child",
                            startTime: now.addingTimeInterval(0.1), endTime: now.addingTimeInterval(0.5),
                            sessionId: "A"))
        try ctx.save()
    }

    /// Polls until `condition` holds, so tests don't depend on how many actor hops
    /// a load takes.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
    }

    // The bug this guards: if the detail panel is driven by the raw selection rather
    // than by the model, it renders an empty chart while the spans are still loading
    // and the user sees a blank panel instead of a progress indicator.
    @Test func selectionEntersLoadingStateBeforeAnySuspension() throws {
        let container = try makeContainer()
        try seed(container)
        let model = TracesListModel()

        model.loadSelection(.trace("t1"), container: container)

        guard case .loading(.trace(let traceId)) = model.detailState else {
            Issue.record("expected .loading, got \(model.detailState)")
            return
        }
        #expect(traceId == "t1")
    }

    // The list has nothing to show until the first reload finishes, so it needs a
    // loading flag to distinguish "still loading" from "no traces recorded".
    @Test func sessionsEnterLoadingStateBeforeAnySuspension() throws {
        let container = try makeContainer()
        try seed(container)
        let model = TracesListModel()

        #expect(model.isLoadingSessions == false)
        model.reloadSessions(container: container)
        #expect(model.isLoadingSessions)
    }

    @Test func sessionLoadingFlagClearsOnceLoaded() async throws {
        let container = try makeContainer()
        try seed(container)
        let model = TracesListModel()

        model.reloadSessions(container: container)
        await waitUntil { !model.sessions.isEmpty }
        await waitUntil { !model.isLoadingSessions }

        #expect(model.isLoadingSessions == false)
        #expect(model.sessions.map(\.id) == ["A"])
    }

    @Test func sessionLoadingFlagClearsWhenStoreIsEmpty() async throws {
        let container = try makeContainer()
        let model = TracesListModel()

        model.reloadSessions(container: container)
        await waitUntil { !model.isLoadingSessions }

        #expect(model.isLoadingSessions == false)
        #expect(model.sessions.isEmpty)
    }

    @Test func selectionResolvesToLoadedSpans() async throws {
        let container = try makeContainer()
        try seed(container)
        let model = TracesListModel()

        model.loadSelection(.trace("t1"), container: container)
        await waitUntil { if case .loaded = model.detailState { return true }; return false }

        guard case .loaded(.trace, let spans) = model.detailState else {
            Issue.record("expected .loaded, got \(model.detailState)")
            return
        }
        #expect(spans.map(\.spanId) == ["r1", "c1"])
    }

    @Test func sessionSelectionLoadsEveryTraceOfTheSession() async throws {
        let container = try makeContainer()
        try seed(container)
        let model = TracesListModel()

        model.reloadSessions(container: container)
        await waitUntil { !model.sessions.isEmpty }

        model.loadSelection(.session("A"), container: container)
        await waitUntil { if case .loaded = model.detailState { return true }; return false }

        guard case .loaded(.session, let spans) = model.detailState else {
            Issue.record("expected .loaded, got \(model.detailState)")
            return
        }
        #expect(Set(spans.map(\.spanId)) == ["r1", "c1"])
    }

    @Test func clearingSelectionReturnsToEmpty() throws {
        let container = try makeContainer()
        let model = TracesListModel()

        model.loadSelection(.trace("t1"), container: container)
        model.loadSelection(nil, container: container)

        guard case .empty = model.detailState else {
            Issue.record("expected .empty, got \(model.detailState)")
            return
        }
    }

    // A slow load for an abandoned selection must not overwrite the newer one.
    @Test func staleSelectionResultDoesNotOverwriteNewerSelection() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1", name: "first",
                            startTime: now, endTime: now.addingTimeInterval(1)))
        ctx.insert(OTLPSpan(traceId: "t2", spanId: "s2", name: "second",
                            startTime: now, endTime: now.addingTimeInterval(1)))
        try ctx.save()
        let model = TracesListModel()

        model.loadSelection(.trace("t1"), container: container)
        model.loadSelection(.trace("t2"), container: container)
        await waitUntil { if case .loaded = model.detailState { return true }; return false }

        guard case .loaded(.trace(let traceId), let spans) = model.detailState else {
            Issue.record("expected .loaded, got \(model.detailState)")
            return
        }
        #expect(traceId == "t2")
        #expect(spans.map(\.spanId) == ["s2"])
    }
}
