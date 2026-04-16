# Metrics Dashboard Design

**Date:** 2026-04-16
**Status:** Approved

## Overview

A metrics dashboard screen for Teloscope that aggregates Claude Code usage data from stored OTLPSpan records. Users can filter by date range and model name, and view key metrics as widgets arranged in a grid.

Widget add/edit/delete is out of scope for this iteration; widgets are fixed.

---

## Scope

### In scope
- Total cost (USD, calculated from token counts × hardcoded model pricing)
- Total token counts (input, output, cache read)
- Total session count
- Approval rate (pie chart: accepted vs rejected tool decisions)
- Model distribution (pie chart: LLM request counts per model)
- Date range filter: presets (Today, 7 days, 30 days, This Month) + custom date picker
- Model name filter: multi-select from available models in the dataset

### Out of scope
- Widget add/edit/delete (next iteration)
- Commit count, PR count, lines written (no reliable span attribute)
- Real-time cost from Claude API (cost is approximated from token × rate)

---

## Architecture

### Data Flow

```
MetricsView (@Query allSpans)
    │
    ▼
MetricsDashboardModel (@Observable)
    ├── dateRange: DateInterval
    ├── selectedModels: Set<String>
    ├── availableModels: [String]      ← derived from date-filtered spans, ignores model filter (so deselecting all models doesn't empty the list)
    ├── metrics: MetricsSummary?       ← nil while computing
    └── onChange(dateRange / selectedModels)
            └── Task { await Task.yield(); compute → metrics }
```

When `allSpans` changes (new OTLP data arrives), `MetricsView` passes the updated array to `MetricsDashboardModel.update(spans:)`, which re-triggers aggregation.

### Concurrency

Aggregation runs in a `Task { @MainActor in }` with `await Task.yield()` before computation, allowing SwiftUI to render the loading state first. Rapid filter changes cancel the previous task via `task?.cancel()`.

---

## Data Model

### MetricsSummary

```swift
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
}
```

`approvalRate` is computed as `Double(approvalCount) / Double(approvalCount + rejectionCount)`.

### ModelPricing

Hardcoded USD per 1M tokens. Unknown models contribute 0 to cost (displayed with a note).

| Model | Input | Output | Cache Read |
|-------|-------|--------|------------|
| claude-opus-4 | $15.00 | $75.00 | $1.50 |
| claude-sonnet-4 | $3.00 | $15.00 | $0.30 |
| claude-haiku-4-5 | $0.80 | $4.00 | $0.08 |

Prefix matching is used (e.g. `"claude-sonnet-4-6"` matches `"claude-sonnet-4"`).

### Span Attribute Mapping

| Metric | Span name prefix | Attribute key |
|--------|-----------------|---------------|
| Tokens / Cost / Model | `claude_code.llm_request` | `input_tokens`, `output_tokens`, `cache_read_tokens`, `model` |
| Approval rate | `claude_code.tool.blocked_on_user` | `decision` ("accept" / "reject") |
| Session count | any | `session.id` (distinct values) |

---

## UI Layout

```
┌─────────────────────────────────────────────────────────┐
│ [Today] [7d] [30d] [This Month] [Custom: Apr 1–16 ▼]    │  ← FilterBar (toolbar style)
│ Model: [All ▼]  (multi-select popover)                   │
├─────────────────────────────────────────────────────────┤
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐      │
│ │  Total Cost  │ │ Total Tokens │ │   Sessions   │      │  ← StatWidget (GroupBox)
│ │   $12.34     │ │  1,234,567   │ │     42       │      │
│ └──────────────┘ └──────────────┘ └──────────────┘      │
│ ┌──────────────────────┐ ┌──────────────────────┐        │
│ │   Approval Rate      │ │  Model Distribution  │        │  ← PieWidget (SectorMark)
│ │   ◯ 78%  approved    │ │  ◯ opus 60%          │        │
│ │   ✓ 35  ✗ 10         │ │    sonnet 40%        │        │
│ └──────────────────────┘ └──────────────────────┘        │
└─────────────────────────────────────────────────────────┘
```

- **Grid**: `LazyVGrid` with `adaptive(minimum: 200)` columns
- **StatWidget**: `GroupBox` with large primary value, secondary breakdown text
- **PieWidget**: Swift Charts `SectorMark`, legend on the right
- **Loading state**: widgets show `ProgressView` overlay while `metrics == nil`
- **Empty state**: `ContentUnavailableView` when no spans exist in range

---

## File Structure

```
Teloscope/
├── Models/
│   └── ModelPricing.swift
├── ViewModels/
│   ├── MetricsDashboardModel.swift
│   └── MetricsSummary.swift
└── Views/
    └── Metrics/
        ├── MetricsView.swift
        ├── FilterBarView.swift
        ├── StatWidgetView.swift
        └── PieWidgetView.swift

TeloscopeTests/
├── Models/
│   └── ModelPricingTests.swift
└── ViewModels/
    └── MetricsDashboardModelTests.swift
```

**Existing files modified:**
- `Views/MainView.swift` — replace `ContentUnavailableView` placeholder with `MetricsView`
- `Localizable.xcstrings` — add EN keys + JA translations for new UI strings

---

## Testing

All tests are pure logic (no SwiftData, no UI). `OTLPSpan` instances are constructed in-memory.

**ModelPricingTests:**
- Known model returns correct per-token cost
- Unknown model returns 0 cost
- Prefix matching works (e.g. `claude-sonnet-4-6` → sonnet pricing)

**MetricsDashboardModelTests (via MetricsSummary):**
- Token totals sum correctly across multiple spans
- Session count deduplicates by `session.id`
- Approval rate: correct ratio, nil when no decision data
- Model distribution: sorted by request count descending
- Date range filter excludes spans outside the interval
- Model filter excludes non-selected models
