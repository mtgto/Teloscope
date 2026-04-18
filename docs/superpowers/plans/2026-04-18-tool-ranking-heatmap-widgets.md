# Tool Ranking & Usage Heatmap Widgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two new Metrics widgets — a horizontal bar chart showing tool call frequency, and a weekday×hour heatmap showing when Claude Code is used.

**Architecture:** Both widgets source data from the existing `OTLPSpan` table (already queried by `MetricsRepository`). `MetricsSummary` gains two new computed properties (`toolRanking`, `usageHeatmap`) populated in its `init`. Each widget gets its own SwiftUI view file following the existing `*WidgetView` pattern. Both are added to the `metricsGrid` in `MetricsView`.

**Tech Stack:** SwiftUI, Swift Charts (`BarMark`), Swift Testing (tests)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Teloscope/ViewModels/MetricsSummary.swift` | Modify | Add `toolRanking` and `usageHeatmap` properties + aggregation logic |
| `Teloscope/Views/Metrics/BarWidgetView.swift` | Create | Horizontal bar chart widget for tool rankings |
| `Teloscope/Views/Metrics/HeatmapWidgetView.swift` | Create | 7×24 grid heatmap for usage by weekday and hour |
| `Teloscope/Views/Metrics/MetricsView.swift` | Modify | Add `toolRankingWidget` and `usageHeatmapWidget` calls to `metricsGrid` |
| `TeloscopeTests/ViewModels/MetricsSummaryTests.swift` | Create | Unit tests for `toolRanking` and `usageHeatmap` aggregation |

---

## Task 1: Add `toolRanking` to `MetricsSummary`

**Files:**
- Modify: `Teloscope/ViewModels/MetricsSummary.swift`
- Create: `TeloscopeTests/ViewModels/MetricsSummaryTests.swift`

- [ ] **Step 1: Create the test file**

```swift
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
}
```

- [ ] **Step 2: Write failing tests for `toolRanking`**

Add inside `MetricsSummaryTests`:

```swift
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
```

- [ ] **Step 3: Run tests to verify they fail (compile error expected)**

```bash
cd /Users/user/work/cocoa/Teloscope && xcodebuild test \
  -project Teloscope.xcodeproj -scheme Teloscope \
  -destination 'platform=macOS' \
  -only-testing:TeloscopeTests/ViewModels/MetricsSummaryTests \
  2>&1 | grep -E "error:|warning: 'toolRanking'|Build FAILED|Build succeeded"
```

Expected: compile error — `toolRanking` not defined on `MetricsSummary`.

- [ ] **Step 4: Add `toolRanking` to `MetricsSummary`**

In `Teloscope/ViewModels/MetricsSummary.swift`, add the property to the struct after `modelDistribution`:

```swift
let toolRanking: [(name: String, count: Int)]
```

In `MetricsSummary.init`, add a new variable before the existing `self.*` assignments:

```swift
var toolCounts: [String: Int] = [:]
for span in spans {
    guard span.name.hasPrefix("claude_code.tool.") else { continue }
    let toolName = String(span.name.dropFirst("claude_code.tool.".count))
    guard toolName != "blocked_on_user" else { continue }
    toolCounts[toolName, default: 0] += 1
}
```

Then add the assignment with the other `self.*` lines:

```swift
self.toolRanking = toolCounts
    .sorted { $0.value > $1.value }
    .map { (name: $0.key, count: $0.value) }
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd /Users/user/work/cocoa/Teloscope && xcodebuild test \
  -project Teloscope.xcodeproj -scheme Teloscope \
  -destination 'platform=macOS' \
  -only-testing:TeloscopeTests/ViewModels/MetricsSummaryTests \
  2>&1 | grep -E "error:|Test.*passed|Test.*failed|Build FAILED|Build succeeded"
```

Expected: all 5 `toolRanking` tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/user/work/cocoa/Teloscope && git add \
  Teloscope/ViewModels/MetricsSummary.swift \
  TeloscopeTests/ViewModels/MetricsSummaryTests.swift && \
git commit -m "feat: add toolRanking aggregation to MetricsSummary"
```

---

## Task 2: Add `usageHeatmap` to `MetricsSummary`

**Files:**
- Modify: `Teloscope/ViewModels/MetricsSummary.swift`
- Modify: `TeloscopeTests/ViewModels/MetricsSummaryTests.swift`

- [ ] **Step 1: Write failing tests for `usageHeatmap`**

Add inside `MetricsSummaryTests` (after the toolRanking tests):

```swift
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
        snap("claude_code.tool.bash",   at: wednesday14h),
        snap("claude_code.llm_request", at: wednesday14h),
    ]
    let summary = MetricsSummary(spans: spans, dateRange: fullRange)
    let total = summary.usageHeatmap.reduce(0) { $0 + $1.count }
    #expect(total == 1)
}

@Test func usageHeatmapEmptyWhenNoLLMSpans() {
    let spans = [snap("claude_code.tool.bash")]
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/user/work/cocoa/Teloscope && xcodebuild test \
  -project Teloscope.xcodeproj -scheme Teloscope \
  -destination 'platform=macOS' \
  -only-testing:TeloscopeTests/ViewModels/MetricsSummaryTests \
  2>&1 | grep -E "error:|warning: 'usageHeatmap'|Build FAILED|Build succeeded"
```

Expected: compile error — `usageHeatmap` not defined.

- [ ] **Step 3: Add `usageHeatmap` to `MetricsSummary`**

Add the property to the struct after `toolRanking`:

```swift
let usageHeatmap: [(weekday: Int, hour: Int, count: Int)]
```

Add aggregation logic in `MetricsSummary.init` (before the `self.*` assignments block, alongside `toolCounts`):

```swift
var heatCounts: [Int: [Int: Int]] = [:]  // weekday(1–7) → hour(0–23) → count
for span in spans where span.name.hasPrefix("claude_code.llm_request") {
    let wd = Calendar.current.component(.weekday, from: span.startTime)
    let hr = Calendar.current.component(.hour,    from: span.startTime)
    heatCounts[wd, default: [:]][hr, default: 0] += 1
}
```

Add the assignment with the other `self.*` lines:

```swift
self.usageHeatmap = heatCounts.flatMap { wd, hours in
    hours.map { hr, cnt in (weekday: wd, hour: hr, count: cnt) }
}
```

- [ ] **Step 4: Run all MetricsSummaryTests to verify they pass**

```bash
cd /Users/user/work/cocoa/Teloscope && xcodebuild test \
  -project Teloscope.xcodeproj -scheme Teloscope \
  -destination 'platform=macOS' \
  -only-testing:TeloscopeTests/ViewModels/MetricsSummaryTests \
  2>&1 | grep -E "error:|Test.*passed|Test.*failed|Build FAILED|Build succeeded"
```

Expected: all 9 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/user/work/cocoa/Teloscope && git add \
  Teloscope/ViewModels/MetricsSummary.swift \
  TeloscopeTests/ViewModels/MetricsSummaryTests.swift && \
git commit -m "feat: add usageHeatmap aggregation to MetricsSummary"
```

---

## Task 3: Create `BarWidgetView` and wire into `MetricsView`

**Files:**
- Create: `Teloscope/Views/Metrics/BarWidgetView.swift`
- Modify: `Teloscope/Views/Metrics/MetricsView.swift`

- [ ] **Step 1: Create `BarWidgetView.swift`**

```swift
// SPDX-License-Identifier: MIT
import SwiftUI
import Charts

struct BarWidgetView: View {
    let title: LocalizedStringKey
    /// Items sorted descending by count. Only the top 10 are displayed.
    let items: [(name: String, count: Int)]

    @Environment(\.redactionReasons) private var redactionReasons

    private var displayItems: [(name: String, count: Int)] { Array(items.prefix(10)) }

    var body: some View {
        GroupBox {
            if redactionReasons.contains(.placeholder) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.gray.opacity(0.3))
                    .frame(height: 100)
            } else if items.isEmpty {
                Text("No data")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                Chart {
                    ForEach(displayItems, id: \.name) { item in
                        BarMark(
                            x: .value("Count", item.count),
                            y: .value("Tool", item.name)
                        )
                        .foregroundStyle(.blue)
                        .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                            Text("\(item.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in AxisValueLabel() }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(displayItems.count) * 22 + 8)
                .padding(8)
            }
        } label: {
            Text(title).unredacted()
        }
    }
}

// MARK: - Previews

#Preview {
    BarWidgetView(
        title: "Tool Usage",
        items: [
            (name: "bash",   count: 42),
            (name: "read",   count: 38),
            (name: "write",  count: 21),
            (name: "edit",   count: 17),
            (name: "grep",   count: 9),
        ]
    )
    .frame(width: 220)
    .padding()
}

#Preview("Empty") {
    BarWidgetView(title: "Tool Usage", items: [])
        .frame(width: 220)
        .padding()
}

#Preview("Loading") {
    BarWidgetView(title: "Tool Usage", items: [])
        .redacted(reason: .placeholder)
        .frame(width: 220)
        .padding()
}
```

- [ ] **Step 2: Add `toolRankingWidget` to `MetricsView` and call it from `metricsGrid`**

In `Teloscope/Views/Metrics/MetricsView.swift`, add this private function alongside the other widget functions (e.g., after `modelWidget`):

```swift
private func toolRankingWidget(_ m: MetricsSummary?) -> some View {
    BarWidgetView(
        title: "Tool Usage",
        items: m?.toolRanking ?? []
    )
}
```

In `metricsGrid`, add `toolRankingWidget(m)` to the `LazyVGrid`:

```swift
private func metricsGrid(_ m: MetricsSummary?) -> some View {
    ScrollView {
        LazyVGrid(columns: columns, spacing: 12) {
            costWidget(m)
            tokensWidget(m)
            sessionsWidget(m)
            approvalWidget(m)
            modelWidget(m)
            toolRankingWidget(m)
            tokensTimelineWidget(m)
            costTimelineWidget(m)
            requestsTimelineWidget(m)
        }
        .padding(12)
    }
}
```

- [ ] **Step 3: Build to verify no compile errors**

```bash
cd /Users/user/work/cocoa/Teloscope && xcodebuild build \
  -project Teloscope.xcodeproj -scheme Teloscope \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|Build FAILED|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 4: Commit**

```bash
cd /Users/user/work/cocoa/Teloscope && git add \
  Teloscope/Views/Metrics/BarWidgetView.swift \
  Teloscope/Views/Metrics/MetricsView.swift && \
git commit -m "feat: add Tool Usage bar chart widget to Metrics dashboard"
```

---

## Task 4: Create `HeatmapWidgetView` and wire into `MetricsView`

**Files:**
- Create: `Teloscope/Views/Metrics/HeatmapWidgetView.swift`
- Modify: `Teloscope/Views/Metrics/MetricsView.swift`

- [ ] **Step 1: Create `HeatmapWidgetView.swift`**

```swift
// SPDX-License-Identifier: MIT
import SwiftUI

struct HeatmapWidgetView: View {
    let title: LocalizedStringKey
    /// Flat list of (weekday, hour, count) entries. weekday uses Calendar convention: 1=Sun…7=Sat.
    let data: [(weekday: Int, hour: Int, count: Int)]

    // Mon–Sun display order. Calendar weekday values: Mon=2, Tue=3, ..., Sat=7, Sun=1.
    private let orderedWeekdays: [(label: String, calValue: Int)] = [
        ("Mon", 2), ("Tue", 3), ("Wed", 4), ("Thu", 5), ("Fri", 6), ("Sat", 7), ("Sun", 1),
    ]

    private var countMap: [Int: [Int: Int]] {
        var map: [Int: [Int: Int]] = [:]
        for entry in data {
            map[entry.weekday, default: [:]][entry.hour] = entry.count
        }
        return map
    }

    private var maxCount: Int { data.map(\.count).max() ?? 1 }

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        GroupBox {
            if redactionReasons.contains(.placeholder) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.gray.opacity(0.3))
                    .frame(height: 86)
            } else {
                let map = countMap
                let maxC = maxCount
                VStack(alignment: .leading, spacing: 2) {
                    // Weekday rows — 24 equal-width flexible cells per row
                    ForEach(orderedWeekdays, id: \.calValue) { wd in
                        HStack(spacing: 0) {
                            Text(wd.label)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)
                                .padding(.trailing, 2)
                            HStack(spacing: 1) {
                                ForEach(0..<24, id: \.self) { hour in
                                    let count = map[wd.calValue]?[hour] ?? 0
                                    let opacity: Double = count == 0
                                        ? 0.08
                                        : max(0.2, Double(count) / Double(maxC))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.accentColor.opacity(opacity))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 10)
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
        } label: {
            Text(title).unredacted()
        }
    }
}

// MARK: - Previews

#Preview {
    HeatmapWidgetView(
        title: "Usage by Time",
        data: {
            var entries: [(weekday: Int, hour: Int, count: Int)] = []
            // Simulate heavier weekday usage during business hours
            for wd in 2...6 {
                for hr in 9...17 {
                    entries.append((weekday: wd, hour: hr, count: Int.random(in: 1...10)))
                }
            }
            entries.append((weekday: 1, hour: 20, count: 3)) // occasional Sunday evening
            return entries
        }()
    )
    .frame(width: 300)
    .padding()
}

#Preview("Empty") {
    HeatmapWidgetView(title: "Usage by Time", data: [])
        .frame(width: 300)
        .padding()
}

#Preview("Loading") {
    HeatmapWidgetView(title: "Usage by Time", data: [])
        .redacted(reason: .placeholder)
        .frame(width: 300)
        .padding()
}
```

- [ ] **Step 2: Add `usageHeatmapWidget` to `MetricsView` and call it from `metricsGrid`**

In `Teloscope/Views/Metrics/MetricsView.swift`, add this private function after `toolRankingWidget`:

```swift
private func usageHeatmapWidget(_ m: MetricsSummary?) -> some View {
    HeatmapWidgetView(
        title: "Usage by Time",
        data: m?.usageHeatmap ?? []
    )
}
```

Update `metricsGrid` to include `usageHeatmapWidget(m)` after `toolRankingWidget(m)`:

```swift
private func metricsGrid(_ m: MetricsSummary?) -> some View {
    ScrollView {
        LazyVGrid(columns: columns, spacing: 12) {
            costWidget(m)
            tokensWidget(m)
            sessionsWidget(m)
            approvalWidget(m)
            modelWidget(m)
            toolRankingWidget(m)
            usageHeatmapWidget(m)
            tokensTimelineWidget(m)
            costTimelineWidget(m)
            requestsTimelineWidget(m)
        }
        .padding(12)
    }
}
```

- [ ] **Step 3: Build to verify no compile errors**

```bash
cd /Users/user/work/cocoa/Teloscope && xcodebuild build \
  -project Teloscope.xcodeproj -scheme Teloscope \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|Build FAILED|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 4: Run full test suite to confirm no regressions**

```bash
cd /Users/user/work/cocoa/Teloscope && xcodebuild test \
  -project Teloscope.xcodeproj -scheme Teloscope \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|Test.*passed|Test.*failed|Build FAILED|Build succeeded"
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/user/work/cocoa/Teloscope && git add \
  Teloscope/Views/Metrics/HeatmapWidgetView.swift \
  Teloscope/Views/Metrics/MetricsView.swift && \
git commit -m "feat: add Usage by Time heatmap widget to Metrics dashboard"
```
