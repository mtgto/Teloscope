# Metrics Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Metrics dashboard screen with cost/token/session/approval/model widgets, date range filter (presets + custom), and model multi-select filter.

**Architecture:** `MetricsView` owns filter state (`dateRange`, `selectedModels`) as `@State` and calls `MetricsDashboardModel.update(spans:dateRange:selectedModels:)` whenever any input changes. The model computes `MetricsSummary` asynchronously via `Task { @MainActor in }` with `await Task.yield()` to show a loading state first. `FilterBarView`, `StatWidgetView`, and `PieWidgetView` are dumb display components that receive data/bindings from `MetricsView`.

**Tech Stack:** SwiftUI, Swift Charts (`SectorMark`), SwiftData (`@Query`), Swift Observation (`@Observable`), Swift Testing (tests)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Teloscope/Models/ModelPricing.swift` | Create | Hardcoded per-token USD rates, prefix-matched |
| `Teloscope/ViewModels/MetricsSummary.swift` | Create | Pure aggregation struct over `[OTLPSpan]` |
| `Teloscope/ViewModels/MetricsDashboardModel.swift` | Create | `@Observable` model holding async aggregation |
| `Teloscope/Views/Metrics/StatWidgetView.swift` | Create | Numeric card widget |
| `Teloscope/Views/Metrics/PieWidgetView.swift` | Create | Pie chart widget (SectorMark) |
| `Teloscope/Views/Metrics/FilterBarView.swift` | Create | Date preset + custom + model multi-select |
| `Teloscope/Views/Metrics/MetricsView.swift` | Create | Dashboard root, owns filter state |
| `Teloscope/Views/MainView.swift` | Modify | Replace Metrics placeholder with MetricsView |
| `Teloscope/Localizable.xcstrings` | Modify | Add EN keys + JA translations |
| `TeloscopeTests/Models/ModelPricingTests.swift` | Create | Unit tests for ModelPricing |
| `TeloscopeTests/ViewModels/MetricsDashboardModelTests.swift` | Create | Unit tests for MetricsSummary aggregation |

---

## Task 1: ModelPricing

**Files:**
- Create: `Teloscope/Models/ModelPricing.swift`
- Create: `TeloscopeTests/Models/ModelPricingTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// TeloscopeTests/Models/ModelPricingTests.swift
// SPDX-License-Identifier: MIT
import Testing
@testable import Teloscope

struct ModelPricingTests {
    @Test func knownModelOpusCost() {
        let p = ModelPricing.pricing(for: "claude-opus-4")
        #expect(p != nil)
        // 1M input tokens at $15/M
        #expect(abs(p!.cost(inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0) - 15.0) < 0.001)
    }

    @Test func prefixMatchingSonnet() {
        // "claude-sonnet-4-6-20251022" should match "claude-sonnet-4" prefix
        let p = ModelPricing.pricing(for: "claude-sonnet-4-6-20251022")
        #expect(p != nil)
        #expect(abs(p!.cost(inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0) - 3.0) < 0.001)
    }

    @Test func unknownModelReturnsNil() {
        #expect(ModelPricing.pricing(for: "gpt-4") == nil)
    }

    @Test func costSumsAllTokenTypes() {
        let p = ModelPricing.pricing(for: "claude-opus-4")!
        // 0 input, 1M output at $75, 1M cache read at $1.5 → $76.5
        #expect(abs(p.cost(inputTokens: 0, outputTokens: 1_000_000, cacheReadTokens: 1_000_000) - 76.5) < 0.001)
    }
}
```

- [ ] **Step 2: Run tests — expect compile error**

```bash
xcodebuild test -scheme Teloscope -destination 'platform=macOS' \
  -only-testing:TeloscopeTests/ModelPricingTests 2>&1 | grep -E "error:|passed|failed"
```

Expected: compile error "cannot find type 'ModelPricing' in scope"

- [ ] **Step 3: Implement ModelPricing**

```swift
// Teloscope/Models/ModelPricing.swift
// SPDX-License-Identifier: MIT
import Foundation

struct ModelPricing {
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cacheReadPerMillion: Double

    // Ordered list — first prefix match wins.
    private static let table: [(prefix: String, pricing: ModelPricing)] = [
        ("claude-opus-4",    ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0,  cacheReadPerMillion: 1.50)),
        ("claude-sonnet-4",  ModelPricing(inputPerMillion:  3.0, outputPerMillion: 15.0,  cacheReadPerMillion: 0.30)),
        ("claude-haiku-4-5", ModelPricing(inputPerMillion:  0.8, outputPerMillion:  4.0,  cacheReadPerMillion: 0.08)),
    ]

    /// Returns pricing for the given model name using prefix matching, or nil if unknown.
    static func pricing(for model: String) -> ModelPricing? {
        table.first { model.hasPrefix($0.prefix) }?.pricing
    }

    /// Total cost in USD for the given token counts.
    func cost(inputTokens: Int64, outputTokens: Int64, cacheReadTokens: Int64) -> Double {
        Double(inputTokens)      * inputPerMillion      / 1_000_000
            + Double(outputTokens)    * outputPerMillion     / 1_000_000
            + Double(cacheReadTokens) * cacheReadPerMillion  / 1_000_000
    }
}
```

- [ ] **Step 4: Run tests — expect 4 passed**

```bash
xcodebuild test -scheme Teloscope -destination 'platform=macOS' \
  -only-testing:TeloscopeTests/ModelPricingTests 2>&1 | grep -E "error:|passed|failed"
```

- [ ] **Step 5: Commit**

```bash
git add Teloscope/Models/ModelPricing.swift TeloscopeTests/Models/ModelPricingTests.swift
git commit -m "feat: add ModelPricing with prefix-matched per-token cost calculation"
```

---

## Task 2: MetricsSummary

**Files:**
- Create: `Teloscope/ViewModels/MetricsSummary.swift`
- Create: `TeloscopeTests/ViewModels/MetricsDashboardModelTests.swift`

`OTLPSpan` is a SwiftData `@Model`, so tests use an in-memory `ModelContainer` (same pattern as `SpanTests`).

- [ ] **Step 1: Write failing tests**

```swift
// TeloscopeTests/ViewModels/MetricsDashboardModelTests.swift
// SPDX-License-Identifier: MIT
import Testing
import SwiftData
@testable import Teloscope

private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
             ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self,
        configurations: config
    )
}

struct MetricsDashboardModelTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func tokenTotalsAreSummed() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [
                SpanAttribute(key: "input_tokens",      value: .int64(100)),
                SpanAttribute(key: "output_tokens",     value: .int64(50)),
                SpanAttribute(key: "cache_read_tokens", value: .int64(20)),
                SpanAttribute(key: "model",             value: .string("claude-opus-4")),
            ]))
        ctx.insert(OTLPSpan(traceId: "t2", spanId: "s2",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [
                SpanAttribute(key: "input_tokens",      value: .int64(200)),
                SpanAttribute(key: "output_tokens",     value: .int64(80)),
                SpanAttribute(key: "cache_read_tokens", value: .int64(10)),
                SpanAttribute(key: "model",             value: .string("claude-sonnet-4")),
            ]))
        try ctx.save()
        let spans = try ctx.fetch(FetchDescriptor<OTLPSpan>())
        let s = MetricsSummary(spans: spans)
        #expect(s.totalInputTokens == 300)
        #expect(s.totalOutputTokens == 130)
        #expect(s.totalCacheReadTokens == 30)
    }

    @Test func sessionCountDeduplicates() throws {
        let ctx = ModelContext(try makeContainer())
        // Two spans same session
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [SpanAttribute(key: "session.id", value: .string("A"))]))
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s2",
            name: "claude_code.tool",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [SpanAttribute(key: "session.id", value: .string("A"))]))
        // One span different session
        ctx.insert(OTLPSpan(traceId: "t2", spanId: "s3",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [SpanAttribute(key: "session.id", value: .string("B"))]))
        try ctx.save()
        let spans = try ctx.fetch(FetchDescriptor<OTLPSpan>())
        #expect(MetricsSummary(spans: spans).sessionCount == 2)
    }

    @Test func approvalRateCalculated() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.tool.blocked_on_user",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [SpanAttribute(key: "decision", value: .string("accept"))]))
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s2",
            name: "claude_code.tool.blocked_on_user",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [SpanAttribute(key: "decision", value: .string("reject"))]))
        try ctx.save()
        let s = MetricsSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(s.hasApprovalData)
        #expect(s.approvalCount == 1)
        #expect(s.rejectionCount == 1)
        #expect(s.approvalRate == 0.5)
    }

    @Test func approvalRateNilWithNoData() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1), attributes: []))
        try ctx.save()
        let s = MetricsSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(!s.hasApprovalData)
        #expect(s.approvalRate == nil)
    }

    @Test func modelDistributionSortedByCount() throws {
        let ctx = ModelContext(try makeContainer())
        for (id, model) in [("s1","claude-opus-4"), ("s2","claude-sonnet-4"), ("s3","claude-sonnet-4")] {
            ctx.insert(OTLPSpan(traceId: "t1", spanId: id,
                name: "claude_code.llm_request",
                startTime: now, endTime: now.addingTimeInterval(1),
                attributes: [SpanAttribute(key: "model", value: .string(model))]))
        }
        try ctx.save()
        let s = MetricsSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(s.modelDistribution.count == 2)
        #expect(s.modelDistribution[0].model == "claude-sonnet-4")
        #expect(s.modelDistribution[0].requestCount == 2)
    }

    @Test func costCalculatedFromPricing() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [
                SpanAttribute(key: "input_tokens",      value: .int64(1_000_000)),
                SpanAttribute(key: "output_tokens",     value: .int64(0)),
                SpanAttribute(key: "cache_read_tokens", value: .int64(0)),
                SpanAttribute(key: "model",             value: .string("claude-opus-4")),
            ]))
        try ctx.save()
        let s = MetricsSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(abs(s.totalCostUSD - 15.0) < 0.001)
    }

    @Test func unknownModelZeroCost() throws {
        let ctx = ModelContext(try makeContainer())
        ctx.insert(OTLPSpan(traceId: "t1", spanId: "s1",
            name: "claude_code.llm_request",
            startTime: now, endTime: now.addingTimeInterval(1),
            attributes: [
                SpanAttribute(key: "input_tokens", value: .int64(1_000_000)),
                SpanAttribute(key: "output_tokens", value: .int64(0)),
                SpanAttribute(key: "cache_read_tokens", value: .int64(0)),
                SpanAttribute(key: "model", value: .string("unknown-model")),
            ]))
        try ctx.save()
        let s = MetricsSummary(spans: try ctx.fetch(FetchDescriptor<OTLPSpan>()))
        #expect(s.totalCostUSD == 0.0)
    }
}
```

- [ ] **Step 2: Run tests — expect compile error**

```bash
xcodebuild test -scheme Teloscope -destination 'platform=macOS' \
  -only-testing:TeloscopeTests/MetricsDashboardModelTests 2>&1 | grep -E "error:|passed|failed"
```

Expected: compile error "cannot find type 'MetricsSummary' in scope"

- [ ] **Step 3: Implement MetricsSummary**

```swift
// Teloscope/ViewModels/MetricsSummary.swift
// SPDX-License-Identifier: MIT
import Foundation

struct MetricsSummary {
    let totalCostUSD: Double
    let totalInputTokens: Int64
    let totalOutputTokens: Int64
    let totalCacheReadTokens: Int64
    let sessionCount: Int
    let approvalCount: Int
    let rejectionCount: Int
    let hasApprovalData: Bool
    let modelDistribution: [(model: String, requestCount: Int)]

    var approvalRate: Double? {
        let total = approvalCount + rejectionCount
        guard total > 0 else { return nil }
        return Double(approvalCount) / Double(total)
    }

    init(spans: [OTLPSpan]) {
        var costUSD = 0.0
        var inputTokens: Int64 = 0
        var outputTokens: Int64 = 0
        var cacheReadTokens: Int64 = 0
        var sessionIds: Set<String> = []
        var approved = 0
        var rejected = 0
        var hasDecisions = false
        var modelCounts: [String: Int] = [:]

        for span in spans {
            if let sid = Self.stringAttr(span, "session.id") {
                sessionIds.insert(sid)
            }
            if span.name.hasPrefix("claude_code.llm_request") {
                let input     = Self.int64Attr(span, "input_tokens")      ?? 0
                let output    = Self.int64Attr(span, "output_tokens")     ?? 0
                let cacheRead = Self.int64Attr(span, "cache_read_tokens") ?? 0
                inputTokens     += input
                outputTokens    += output
                cacheReadTokens += cacheRead
                if let model = Self.stringAttr(span, "model") {
                    modelCounts[model, default: 0] += 1
                    if let p = ModelPricing.pricing(for: model) {
                        costUSD += p.cost(inputTokens: input, outputTokens: output, cacheReadTokens: cacheRead)
                    }
                }
            } else if span.name.hasPrefix("claude_code.tool.blocked_on_user") {
                hasDecisions = true
                switch Self.stringAttr(span, "decision")?.lowercased() {
                case "accept": approved += 1
                case "reject": rejected += 1
                default: break
                }
            }
        }

        self.totalCostUSD         = costUSD
        self.totalInputTokens     = inputTokens
        self.totalOutputTokens    = outputTokens
        self.totalCacheReadTokens = cacheReadTokens
        self.sessionCount         = sessionIds.count
        self.approvalCount        = approved
        self.rejectionCount       = rejected
        self.hasApprovalData      = hasDecisions
        self.modelDistribution    = modelCounts
            .sorted { $0.value > $1.value }
            .map { (model: $0.key, requestCount: $0.value) }
    }

    private static func int64Attr(_ span: OTLPSpan, _ key: String) -> Int64? {
        guard case .int64(let v) = span.attributes.first(where: { $0.key == key })?.value else { return nil }
        return v
    }

    private static func stringAttr(_ span: OTLPSpan, _ key: String) -> String? {
        guard case .string(let v) = span.attributes.first(where: { $0.key == key })?.value else { return nil }
        return v
    }
}
```

- [ ] **Step 4: Run tests — expect 7 passed**

```bash
xcodebuild test -scheme Teloscope -destination 'platform=macOS' \
  -only-testing:TeloscopeTests/MetricsDashboardModelTests 2>&1 | grep -E "error:|passed|failed"
```

- [ ] **Step 5: Commit**

```bash
git add Teloscope/ViewModels/MetricsSummary.swift TeloscopeTests/ViewModels/MetricsDashboardModelTests.swift
git commit -m "feat: add MetricsSummary with TDD"
```

---

## Task 3: MetricsDashboardModel

**Files:**
- Create: `Teloscope/ViewModels/MetricsDashboardModel.swift`

`MetricsView` owns filter state as `@State` and calls `update(spans:dateRange:selectedModels:)` whenever inputs change. The model cancels the previous task on each call, yields so the loading state renders, then computes.

**Model filter behaviour:** model filter applies only to `claude_code.llm_request` spans — cost, tokens, and model distribution respect the filter. Session count and approval rate use all date-filtered spans (they are not per-model concepts).

- [ ] **Step 1: Create MetricsDashboardModel**

```swift
// Teloscope/ViewModels/MetricsDashboardModel.swift
// SPDX-License-Identifier: MIT
import Foundation
import Observation

@Observable
@MainActor
final class MetricsDashboardModel {
    private(set) var availableModels: [String] = []
    private(set) var metrics: MetricsSummary?
    private(set) var isLoading = false

    private var computeTask: Task<Void, Never>?

    func update(spans: [OTLPSpan], dateRange: DateInterval, selectedModels: Set<String>) {
        computeTask?.cancel()
        metrics = nil
        isLoading = true
        computeTask = Task { @MainActor in
            // Yield so SwiftUI renders the loading state before we start computing.
            await Task.yield()
            guard !Task.isCancelled else { return }

            let dateFiltered = spans.filter { dateRange.contains($0.startTime) }

            // Derive model list from date-filtered spans only (ignores model filter so
            // the picker doesn't empty when all models are deselected).
            let modelSet = Set(dateFiltered.compactMap { span -> String? in
                guard span.name.hasPrefix("claude_code.llm_request") else { return nil }
                guard case .string(let m) = span.attributes.first(where: { $0.key == "model" })?.value else { return nil }
                return m
            })
            availableModels = modelSet.sorted()

            // Model filter applies only to LLM request spans.
            let filtered: [OTLPSpan]
            if selectedModels.isEmpty {
                filtered = dateFiltered
            } else {
                filtered = dateFiltered.filter { span in
                    guard span.name.hasPrefix("claude_code.llm_request") else { return true }
                    guard case .string(let m) = span.attributes.first(where: { $0.key == "model" })?.value else { return false }
                    return selectedModels.contains(m)
                }
            }

            guard !Task.isCancelled else { return }
            metrics = MetricsSummary(spans: filtered)
            isLoading = false
        }
    }

    static func defaultDateRange() -> DateInterval {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now.addingTimeInterval(-7 * 24 * 3600))
        return DateInterval(start: start, end: now)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Teloscope -destination 'platform=macOS' 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: Build succeeded

- [ ] **Step 3: Commit**

```bash
git add Teloscope/ViewModels/MetricsDashboardModel.swift
git commit -m "feat: add MetricsDashboardModel with async filter/aggregation"
```

---

## Task 4: StatWidgetView

**Files:**
- Create: `Teloscope/Views/Metrics/StatWidgetView.swift`

- [ ] **Step 1: Create StatWidgetView**

```swift
// Teloscope/Views/Metrics/StatWidgetView.swift
// SPDX-License-Identifier: MIT
import SwiftUI

struct StatWidgetView: View {
    let title: String
    let primaryValue: String
    let rows: [(label: String, value: String)]

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 4) {
                Text(primaryValue)
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !rows.isEmpty {
                    Divider()
                    ForEach(rows, id: \.label) { row in
                        HStack {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Spacer()
                            Text(row.value)
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    StatWidgetView(
        title: "Total Tokens",
        primaryValue: "1,234,567",
        rows: [
            (label: "Input", value: "800,000"),
            (label: "Output", value: "400,000"),
            (label: "Cache Read", value: "34,567"),
        ]
    )
    .frame(width: 220)
    .padding()
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Teloscope -destination 'platform=macOS' 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

- [ ] **Step 3: Commit**

```bash
git add Teloscope/Views/Metrics/StatWidgetView.swift
git commit -m "feat: add StatWidgetView for numeric metric cards"
```

---

## Task 5: PieWidgetView

**Files:**
- Create: `Teloscope/Views/Metrics/PieWidgetView.swift`

- [ ] **Step 1: Create PieWidgetView**

```swift
// Teloscope/Views/Metrics/PieWidgetView.swift
// SPDX-License-Identifier: MIT
import SwiftUI
import Charts

struct PieSlice: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

struct PieWidgetView: View {
    let title: String
    let slices: [PieSlice]
    /// Short text rendered in the donut hole (e.g. "78%"). Pass nil to omit.
    let centerLabel: String?

    var body: some View {
        GroupBox(title) {
            if slices.isEmpty {
                Text("No data")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Chart(slices) { slice in
                            SectorMark(
                                angle: .value("Value", slice.value),
                                innerRadius: .ratio(0.55),
                                angularInset: 1.5
                            )
                            .foregroundStyle(slice.color)
                        }
                        if let label = centerLabel {
                            Text(label)
                                .font(.caption2.bold())
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(width: 80, height: 80)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(slices) { slice in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(slice.color)
                                    .frame(width: 8, height: 8)
                                Text(slice.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}

#Preview {
    PieWidgetView(
        title: "Approval Rate",
        slices: [
            PieSlice(label: "Approved (35)", value: 35, color: .green),
            PieSlice(label: "Rejected (10)", value: 10, color: .red),
        ],
        centerLabel: "78%"
    )
    .frame(width: 260)
    .padding()
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Teloscope -destination 'platform=macOS' 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

- [ ] **Step 3: Commit**

```bash
git add Teloscope/Views/Metrics/PieWidgetView.swift
git commit -m "feat: add PieWidgetView using Swift Charts SectorMark"
```

---

## Task 6: FilterBarView

**Files:**
- Create: `Teloscope/Views/Metrics/FilterBarView.swift`

- [ ] **Step 1: Create FilterBarView**

```swift
// Teloscope/Views/Metrics/FilterBarView.swift
// SPDX-License-Identifier: MIT
import SwiftUI

struct FilterBarView: View {
    let availableModels: [String]
    @Binding var dateRange: DateInterval
    @Binding var selectedModels: Set<String>

    @State private var showCustomPicker = false
    @State private var showModelPicker = false
    @State private var customStart = Date()
    @State private var customEnd = Date()

    private enum Preset: String, CaseIterable {
        case today = "Today"
        case sevenDays = "7 Days"
        case thirtyDays = "30 Days"
        case thisMonth = "This Month"

        func dateInterval() -> DateInterval {
            let now = Date()
            let cal = Calendar.current
            switch self {
            case .today:
                return DateInterval(start: cal.startOfDay(for: now), end: now)
            case .sevenDays:
                return DateInterval(
                    start: cal.startOfDay(for: now.addingTimeInterval(-7 * 24 * 3600)), end: now)
            case .thirtyDays:
                return DateInterval(
                    start: cal.startOfDay(for: now.addingTimeInterval(-30 * 24 * 3600)), end: now)
            case .thisMonth:
                let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
                return DateInterval(start: start, end: now)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Preset.allCases, id: \.self) { preset in
                    Button(preset.rawValue) { dateRange = preset.dateInterval() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button {
                    customStart = dateRange.start
                    customEnd = dateRange.end
                    showCustomPicker = true
                } label: {
                    Label("Custom", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showCustomPicker) { customDatePicker }
            }
            HStack(spacing: 6) {
                Text("Model:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    showModelPicker = true
                } label: {
                    Text(selectedModels.isEmpty
                         ? "All Models"
                         : selectedModels.sorted().joined(separator: ", "))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showModelPicker) { modelPicker }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var customDatePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom Range").font(.headline)
            DatePicker("Start", selection: $customStart, displayedComponents: .date)
            DatePicker("End",   selection: $customEnd,   in: customStart..., displayedComponents: .date)
            HStack {
                Spacer()
                Button("Apply") {
                    let cal = Calendar.current
                    dateRange = DateInterval(
                        start: cal.startOfDay(for: customStart),
                        end:   cal.startOfDay(for: customEnd).addingTimeInterval(86399))
                    showCustomPicker = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(customEnd < customStart)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Filter by Model").font(.headline).padding(.bottom, 4)
            if availableModels.isEmpty {
                Text("No models in range")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(availableModels, id: \.self) { model in
                    Toggle(model, isOn: Binding(
                        get: { selectedModels.contains(model) },
                        set: { if $0 { selectedModels.insert(model) } else { selectedModels.remove(model) } }
                    ))
                    .toggleStyle(.checkbox)
                }
                if !selectedModels.isEmpty {
                    Divider()
                    Button("Clear") { selectedModels.removeAll() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(minWidth: 220)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Teloscope -destination 'platform=macOS' 2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

- [ ] **Step 3: Commit**

```bash
git add Teloscope/Views/Metrics/FilterBarView.swift
git commit -m "feat: add FilterBarView with date presets, custom range picker, and model multi-select"
```

---

## Task 7: MetricsView + MainView + Localizable.xcstrings

**Files:**
- Create: `Teloscope/Views/Metrics/MetricsView.swift`
- Modify: `Teloscope/Views/MainView.swift` line 38
- Modify: `Teloscope/Localizable.xcstrings`

- [ ] **Step 1: Create MetricsView**

```swift
// Teloscope/Views/Metrics/MetricsView.swift
// SPDX-License-Identifier: MIT
import SwiftUI
import SwiftData

struct MetricsView: View {
    @Query(sort: \OTLPSpan.startTime, order: .reverse) private var allSpans: [OTLPSpan]
    @State private var dashboardModel = MetricsDashboardModel()
    @State private var dateRange: DateInterval = MetricsDashboardModel.defaultDateRange()
    @State private var selectedModels: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            FilterBarView(
                availableModels: dashboardModel.availableModels,
                dateRange: $dateRange,
                selectedModels: $selectedModels
            )
            .background(.bar)
            Divider()
            Group {
                if dashboardModel.isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let m = dashboardModel.metrics, m.sessionCount > 0 || m.totalInputTokens > 0 {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            costWidget(m)
                            tokensWidget(m)
                            sessionsWidget(m)
                            approvalWidget(m)
                            modelWidget(m)
                        }
                        .padding(12)
                    }
                } else {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("No spans recorded in the selected range.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Metrics")
        .onAppear { refresh() }
        .onChange(of: allSpans)       { refresh() }
        .onChange(of: dateRange)      { refresh() }
        .onChange(of: selectedModels) { refresh() }
    }

    private func refresh() {
        dashboardModel.update(spans: allSpans, dateRange: dateRange, selectedModels: selectedModels)
    }

    private func costWidget(_ m: MetricsSummary) -> some View {
        StatWidgetView(
            title: "Total Cost",
            primaryValue: m.totalCostUSD.formatted(.currency(code: "USD")),
            rows: []
        )
    }

    private func tokensWidget(_ m: MetricsSummary) -> some View {
        let total = m.totalInputTokens + m.totalOutputTokens + m.totalCacheReadTokens
        return StatWidgetView(
            title: "Total Tokens",
            primaryValue: total.formatted(.number),
            rows: [
                (label: "Input",      value: m.totalInputTokens.formatted(.number)),
                (label: "Output",     value: m.totalOutputTokens.formatted(.number)),
                (label: "Cache Read", value: m.totalCacheReadTokens.formatted(.number)),
            ]
        )
    }

    private func sessionsWidget(_ m: MetricsSummary) -> some View {
        StatWidgetView(
            title: "Sessions",
            primaryValue: m.sessionCount.formatted(.number),
            rows: []
        )
    }

    private func approvalWidget(_ m: MetricsSummary) -> some View {
        let slices: [PieSlice]
        let centerLabel: String?
        if m.hasApprovalData {
            slices = [
                PieSlice(label: "Approved (\(m.approvalCount))", value: Double(m.approvalCount), color: .green),
                PieSlice(label: "Rejected (\(m.rejectionCount))", value: Double(m.rejectionCount), color: .red),
            ]
            centerLabel = m.approvalRate.map { "\(Int($0 * 100))%" }
        } else {
            slices = []
            centerLabel = nil
        }
        return PieWidgetView(title: "Approval Rate", slices: slices, centerLabel: centerLabel)
    }

    private func modelWidget(_ m: MetricsSummary) -> some View {
        let palette: [Color] = [.blue, .orange, .green, .purple, .teal, .pink]
        let slices = m.modelDistribution.enumerated().map { i, entry in
            PieSlice(
                label: "\(entry.model) (\(entry.requestCount))",
                value: Double(entry.requestCount),
                color: palette[i % palette.count]
            )
        }
        return PieWidgetView(title: "Model Distribution", slices: slices, centerLabel: nil)
    }
}

#Preview {
    MetricsView()
        .modelContainer(
            for: [ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
                  ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self],
            inMemory: true
        )
}
```

- [ ] **Step 2: Update MainView.swift — replace the Metrics placeholder**

In `Teloscope/Views/MainView.swift`, find line 38:
```swift
case .metrics: ContentUnavailableView("Metrics", systemImage: "chart.line.uptrend.xyaxis", description: Text("Coming soon"))
```
Replace with:
```swift
case .metrics: MetricsView()
```

- [ ] **Step 3: Add Japanese translations to Localizable.xcstrings**

Open `Teloscope/Localizable.xcstrings`. Inside the `"strings"` JSON object, add the following entries (check for existing keys first — skip any already present):

```json
"Total Cost" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "合計コスト" } }
  }
},
"Total Tokens" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "合計トークン数" } }
  }
},
"Sessions" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "セッション数" } }
  }
},
"Approval Rate" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "承認率" } }
  }
},
"Model Distribution" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "モデル分布" } }
  }
},
"Today" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "今日" } }
  }
},
"7 Days" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "7日間" } }
  }
},
"30 Days" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "30日間" } }
  }
},
"This Month" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "今月" } }
  }
},
"Custom" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "カスタム" } }
  }
},
"Custom Range" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "カスタム期間" } }
  }
},
"Model:" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "モデル：" } }
  }
},
"All Models" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "すべてのモデル" } }
  }
},
"Filter by Model" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "モデルで絞り込む" } }
  }
},
"No models in range" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "期間内にモデルデータなし" } }
  }
},
"No Data" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "データなし" } }
  }
},
"No spans recorded in the selected range." : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "選択期間内にスパンが記録されていません。" } }
  }
},
"Apply" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "適用" } }
  }
},
"Clear" : {
  "localizations" : {
    "ja" : { "stringUnit" : { "state" : "translated", "value" : "クリア" } }
  }
}
```

- [ ] **Step 4: Run all tests**

```bash
xcodebuild test -scheme Teloscope -destination 'platform=macOS' 2>&1 | grep -E "error:|Test Suite|passed|failed"
```

Expected: all tests pass (no new failures)

- [ ] **Step 5: Commit**

```bash
git add Teloscope/Views/Metrics/MetricsView.swift \
        Teloscope/Views/MainView.swift \
        Teloscope/Localizable.xcstrings
git commit -m "feat: add MetricsView dashboard and wire up to navigation"
```
