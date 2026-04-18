// SPDX-License-Identifier: MIT
import Testing
import Foundation
@testable import Teloscope

struct MetricsSummaryTests {
    // Fixed point in time: a Wednesday at 14:00 UTC.
    // timeIntervalSince1970 = 1_000_000 is 1970-01-12 Monday 13:46:40 UTC.
    // Use a known weekday/hour to keep heatmap tests deterministic.
    // 2024-01-03 is a Wednesday. Noon UTC.
    private let wednesday14h = Date(timeIntervalSince1970: 1_704_279_600) // 2024-01-03 13:00 UTC
    private let fullRange = DateInterval(start: .distantPast, end: .distantFuture)

    private func snap(_ name: String, at date: Date = Date()) -> SpanSnapshot {
        SpanSnapshot(OTLPSpan(
            traceId: "t", spanId: UUID().uuidString,
            name: name,
            startTime: date, endTime: date.addingTimeInterval(1)
        ))
    }

    // MARK: - toolRanking

    @Test func toolRankingCountsToolSpans() {
        let spans = [
            snap("claude_code.tool.bash"),
            snap("claude_code.tool.bash"),
            snap("claude_code.tool.read"),
        ]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        #expect(summary.toolRanking.count == 2)
        #expect(summary.toolRanking[0] == (name: "bash", count: 2))
        #expect(summary.toolRanking[1] == (name: "read", count: 1))
    }

    @Test func toolRankingExcludesBlockedOnUser() {
        let spans = [
            snap("claude_code.tool.bash"),
            snap("claude_code.tool.blocked_on_user"),
        ]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        #expect(summary.toolRanking.count == 1)
        #expect(summary.toolRanking[0].name == "bash")
    }

    @Test func toolRankingIgnoresNonToolSpans() {
        let spans = [
            snap("claude_code.llm_request"),
            snap("claude_code.tool.bash"),
        ]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        #expect(summary.toolRanking.count == 1)
        #expect(summary.toolRanking[0].name == "bash")
    }

    @Test func toolRankingSortedDescending() {
        let spans = [
            snap("claude_code.tool.read"),
            snap("claude_code.tool.bash"),
            snap("claude_code.tool.bash"),
            snap("claude_code.tool.bash"),
            snap("claude_code.tool.read"),
            snap("claude_code.tool.write"),
        ]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        let names = summary.toolRanking.map(\.name)
        #expect(names == ["bash", "read", "write"])
    }

    @Test func toolRankingEmptyWhenNoToolSpans() {
        let spans = [snap("claude_code.llm_request")]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        #expect(summary.toolRanking.isEmpty)
    }
}
