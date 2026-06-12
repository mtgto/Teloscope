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

    private func snap(_ name: String, at date: Date = Date(), toolName: String? = nil) -> SpanSnapshot {
        SpanSnapshot(OTLPSpan(
            traceId: "t", spanId: UUID().uuidString,
            name: name,
            startTime: date, endTime: date.addingTimeInterval(1),
            toolName: toolName
        ))
    }

    // MARK: - toolRanking

    @Test func toolRankingCountsToolSpans() {
        let spans = [
            snap("claude_code.tool", toolName: "bash"),
            snap("claude_code.tool", toolName: "bash"),
            snap("claude_code.tool", toolName: "read"),
        ]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        #expect(summary.toolRanking.count == 2)
        #expect(summary.toolRanking[0] == (name: "bash", count: 2))
        #expect(summary.toolRanking[1] == (name: "read", count: 1))
    }

    @Test func toolRankingExcludesBlockedOnUser() {
        let spans = [
            snap("claude_code.tool", toolName: "bash"),
            snap("claude_code.tool.blocked_on_user"),
        ]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        #expect(summary.toolRanking.count == 1)
        #expect(summary.toolRanking[0].name == "bash")
    }

    @Test func toolRankingIgnoresNonToolSpans() {
        let spans = [
            snap("claude_code.llm_request"),
            snap("claude_code.tool", toolName: "bash"),
        ]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        #expect(summary.toolRanking.count == 1)
        #expect(summary.toolRanking[0].name == "bash")
    }

    @Test func toolRankingIgnoresToolSpansWithoutToolName() {
        let spans = [
            snap("claude_code.tool"),              // no toolName attribute
            snap("claude_code.tool", toolName: "bash"),
        ]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        #expect(summary.toolRanking.count == 1)
        #expect(summary.toolRanking[0].name == "bash")
    }

    @Test func toolRankingSortedDescending() {
        let spans = [
            snap("claude_code.tool", toolName: "read"),
            snap("claude_code.tool", toolName: "bash"),
            snap("claude_code.tool", toolName: "bash"),
            snap("claude_code.tool", toolName: "bash"),
            snap("claude_code.tool", toolName: "read"),
            snap("claude_code.tool", toolName: "write"),
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

    @Test func toolRankingTieBreaksByNameAlphabetically() {
        let spans = [
            snap("claude_code.tool", toolName: "write"),
            snap("claude_code.tool", toolName: "bash"),
        ]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        let names = summary.toolRanking.map(\.name)
        #expect(names == ["bash", "write"])
    }

    // MARK: - usageHeatmap

    @Test func usageHeatmapBucketsLLMRequestsByWeekdayAndHour() {
        // wednesday14h is Wednesday. Verify weekday is 4 (Wed) in Calendar.current.
        // Calendar.weekday: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
        let expectedWeekday = Calendar.current.component(.weekday, from: wednesday14h)
        let expectedHour    = Calendar.current.component(.hour,    from: wednesday14h)

        let spans = [
            snap("claude_code.llm_request", at: wednesday14h),
            snap("claude_code.llm_request", at: wednesday14h),
        ]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        let entry = summary.usageHeatmap.first(where: {
            $0.weekday == expectedWeekday && $0.hour == expectedHour
        })
        #expect(entry?.count == 2)
    }

    @Test func usageHeatmapIgnoresNonLLMSpans() {
        let spans = [
            snap("claude_code.tool", at: wednesday14h, toolName: "bash"),
            snap("claude_code.llm_request", at: wednesday14h),
        ]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        let total = summary.usageHeatmap.reduce(0) { $0 + $1.count }
        #expect(total == 1)
    }

    @Test func usageHeatmapEmptyWhenNoLLMSpans() {
        let spans = [snap("claude_code.tool", toolName: "bash")]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        #expect(summary.usageHeatmap.isEmpty)
    }

    @Test func usageHeatmapAccumulatesAcrossDays() {
        // Two different days at the same hour should land in different weekday buckets.
        let day1 = wednesday14h                              // Wednesday
        let day2 = wednesday14h.addingTimeInterval(86400)   // Thursday
        let spans = [
            snap("claude_code.llm_request", at: day1),
            snap("claude_code.llm_request", at: day2),
        ]
        let summary = MetricsSummary(spans: spans, dateRange: fullRange)
        #expect(summary.usageHeatmap.count == 2)
        #expect(summary.usageHeatmap.allSatisfy { $0.count == 1 })
    }

    // MARK: - Helpers for LogEvent

    private func claudeSnap(skillName: String?, at date: Date = Date()) -> LogEventSnapshot {
        LogEventSnapshot(LogEvent(eventName: "skill_activated", timestamp: date, skillName: skillName))
    }

    private func userSnap(skillName: String?, at date: Date = Date()) -> LogEventSnapshot {
        LogEventSnapshot(LogEvent(eventName: "user_prompt", timestamp: date, skillName: skillName, invocationTrigger: "user-slash"))
    }

    // MARK: - claudeSkillRanking

    @Test func claudeSkillRankingCountsSkillActivatedEvents() {
        let events = [
            claudeSnap(skillName: "superpowers:brainstorming"),
            claudeSnap(skillName: "superpowers:brainstorming"),
            claudeSnap(skillName: "update-config"),
        ]
        let summary = MetricsSummary(spans: [], logEvents: events, dateRange: fullRange)
        #expect(summary.claudeSkillRanking.count == 2)
        #expect(summary.claudeSkillRanking[0] == (name: "superpowers:brainstorming", count: 2))
        #expect(summary.claudeSkillRanking[1] == (name: "update-config", count: 1))
    }

    @Test func claudeSkillRankingIgnoresNilSkillName() {
        let events = [claudeSnap(skillName: "superpowers:brainstorming"), claudeSnap(skillName: nil)]
        let summary = MetricsSummary(spans: [], logEvents: events, dateRange: fullRange)
        #expect(summary.claudeSkillRanking.count == 1)
        #expect(summary.claudeSkillRanking[0].name == "superpowers:brainstorming")
    }

    @Test func claudeSkillRankingIsEmptyWithNoEvents() {
        let summary = MetricsSummary(spans: [], logEvents: [], dateRange: fullRange)
        #expect(summary.claudeSkillRanking.isEmpty)
    }

    // MARK: - userSkillRanking

    @Test func userSkillRankingCountsUserPromptEvents() {
        let events = [
            userSnap(skillName: "otel-test"),
            userSnap(skillName: "otel-test"),
            userSnap(skillName: "simplify"),
        ]
        let summary = MetricsSummary(spans: [], logEvents: events, dateRange: fullRange)
        #expect(summary.userSkillRanking.count == 2)
        #expect(summary.userSkillRanking[0] == (name: "otel-test", count: 2))
        #expect(summary.userSkillRanking[1] == (name: "simplify", count: 1))
    }

    @Test func userSkillRankingIgnoresNilSkillName() {
        let events = [userSnap(skillName: "otel-test"), userSnap(skillName: nil)]
        let summary = MetricsSummary(spans: [], logEvents: events, dateRange: fullRange)
        #expect(summary.userSkillRanking.count == 1)
        #expect(summary.userSkillRanking[0].name == "otel-test")
    }

    @Test func skillRankingsAreSeparatedByEventName() {
        let events = [
            claudeSnap(skillName: "simplify"),
            userSnap(skillName: "otel-test"),
        ]
        let summary = MetricsSummary(spans: [], logEvents: events, dateRange: fullRange)
        #expect(summary.claudeSkillRanking.count == 1)
        #expect(summary.claudeSkillRanking[0].name == "simplify")
        #expect(summary.userSkillRanking.count == 1)
        #expect(summary.userSkillRanking[0].name == "otel-test")
    }

    // MARK: - linesOfCode

    private func ndp(_ lineType: String, value: Double) -> NumberDataPointSnapshot {
        NumberDataPointSnapshot(OTLPNumberDataPoint(
            metricName: "claude_code.lines_of_code.count",
            metricUnit: "{lines}",
            timestamp: Date(),
            value: value,
            attributesJSON: "{\"type\":\"\(lineType)\"}"
        ))
    }

    @Test func linesOfCodeSumsAddedAndRemoved() {
        let points = [ndp("added", value: 100), ndp("added", value: 20), ndp("removed", value: 30)]
        let summary = MetricsSummary(spans: [], numberDataPoints: points, dateRange: fullRange)
        #expect(summary.linesOfCodeAdded == 120)
        #expect(summary.linesOfCodeRemoved == 30)
    }

    @Test func linesOfCodeZeroWhenNoDataPoints() {
        let summary = MetricsSummary(spans: [], dateRange: fullRange)
        #expect(summary.linesOfCodeAdded == 0)
        #expect(summary.linesOfCodeRemoved == 0)
    }

    @Test func linesOfCodeIgnoresOtherMetricNames() {
        let other = NumberDataPointSnapshot(OTLPNumberDataPoint(
            metricName: "other.metric", metricUnit: "", timestamp: Date(),
            value: 999, attributesJSON: "{\"type\":\"added\"}"
        ))
        let summary = MetricsSummary(spans: [], numberDataPoints: [other], dateRange: fullRange)
        #expect(summary.linesOfCodeAdded == 0)
    }
}
