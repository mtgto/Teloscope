# MetricsView: Lines of Code Widget Design

## Context

Teloscope currently displays Claude Code usage metrics (tokens, cost, tool usage, etc.) by parsing OTLP **span** data. OTLP **metrics** data (such as `claude_code.lines_of_code.count`) is received and stored as raw binary (`ResourceMetrics.rawData`) with a placeholder comment "Visualization is planned for a future phase."

This design implements the first metrics visualization: a `StatWidgetView` showing total lines of code for the selected date range, with per-attribute breakdown rows (e.g., added/removed) if the metric includes dimensional attributes.

---

## Architecture

### Full Metrics Model Approach

Follow the same pattern as `LogEvent` (a standalone SwiftData model, no FK to `ResourceLogs`):

1. **New model** `OTLPNumberDataPoint` — one SwiftData record per numeric OTLP data point
2. **Updated ingestion** — parse `ResourceMetrics` proto instead of storing raw bytes
3. **Updated repository** — fetch `OTLPNumberDataPoint` alongside spans and log events
4. **Updated summary** — aggregate lines_of_code totals and breakdown
5. **New widget** — `StatWidgetView` in `MetricsView`

---

## Components

### 1. `OTLPNumberDataPoint` (new SwiftData model)

**File:** `Teloscope/Models/OTLPNumberDataPoint.swift`

Fields:
- `metricName: String` — e.g. `"claude_code.lines_of_code.count"`
- `metricUnit: String` — e.g. `"{lines}"` or `""`
- `timestamp: Date` — from `dataPoint.timeUnixNano` (nanoseconds → Date)
- `value: Double` — from `dataPoint.value` (`.asDouble` or `.asInt` converted)
- `attributesJSON: String` — JSON-encoded `[String: String]` of the data point's attributes

Covers both `Sum` and `Gauge` metric types (the two types that produce `NumberDataPoint`).

### 2. Ingestion — `OTLPIngestionService.ingestMetrics()`

**File:** `Teloscope/Ingestion/OTLPIngestionService.swift`

Replace the current stub (which just inserts a `ResourceMetrics` record) with:

```
Opentelemetry_Proto_Collector_Metrics_V1_ExportMetricsServiceRequest.init(serializedBytes:)
  → iterate resourceMetrics → scopeMetrics → metrics
    → for Sum and Gauge metrics, iterate NumberDataPoint[]
      → convert timeUnixNano to Date, asDouble/asInt to Double
      → encode attributes to JSON [String:String]
      → insert OTLPNumberDataPoint into modelContext
```

`ResourceMetrics` model is kept in place (no migration needed) but no longer inserted for new data.

### 3. `NumberDataPointSnapshot` (new struct in MetricsSummary.swift)

Mirrors `SpanSnapshot` / `LogEventSnapshot` — a value-type copy for off-main-thread computation:

```swift
struct NumberDataPointSnapshot {
    let metricName: String
    let timestamp: Date
    let value: Double
    let attributesJSON: String
}
```

### 4. `MetricsRepository.computeSummary()`

**File:** `Teloscope/ViewModels/MetricsRepository.swift`

Add a third fetch alongside spans and log events:

```swift
let metricDescriptor = FetchDescriptor<OTLPNumberDataPoint>(
    predicate: #Predicate { $0.timestamp >= start && $0.timestamp <= end }
)
let numberDataPoints = try modelContext.fetch(metricDescriptor).map { NumberDataPointSnapshot($0) }
```

Pass `numberDataPoints` into `MetricsSummary(spans:logEvents:numberDataPoints:dateRange:)`.

### 5. `MetricsSummary` additions

**File:** `Teloscope/ViewModels/MetricsSummary.swift`

New computed properties:
- `linesOfCodeTotal: Int64` — sum of all `value` where `metricName == "claude_code.lines_of_code.count"`
- `linesOfCodeAdded: Int64` — sum of `value` where `type == "added"`
- `linesOfCodeRemoved: Int64` — sum of `value` where `type == "removed"`

The `type` attribute is documented as always being either `"added"` or `"removed"` (ref: Claude Code telemetry docs).

Aggregation strategy: treat all data points as **additive** (DELTA temporality). This works correctly for Claude Code which emits per-operation counts.

The `type` attribute is always `"added"` or `"removed"` per the Claude Code telemetry spec.

### 6. `MetricsView` — new widget + notification

**File:** `Teloscope/Views/Metrics/MetricsView.swift`

Add `linesOfCodeWidget` using `StatWidgetView`:
- Primary value: `(linesOfCodeAdded + linesOfCodeRemoved).formatted(.number)` (total)
- Rows: `[("Added", linesOfCodeAdded.formatted(.number)), ("Removed", linesOfCodeRemoved.formatted(.number))]`
- Position: after `sessionsWidget` (before `approvalWidget`)

Also add `.otlpMetricsIngested` to the existing notification listeners so the dashboard refreshes when new metric data arrives.

### 7. Localizable.xcstrings

Add English key `"Lines of Code"` with Japanese translation `"コード行数"`.

---

## File Change Summary

| File | Change |
|------|--------|
| `Teloscope/Models/OTLPNumberDataPoint.swift` | **New** — SwiftData model |
| `Teloscope/Ingestion/OTLPIngestionService.swift` | Update `ingestMetrics()` |
| `Teloscope/ViewModels/MetricsSummary.swift` | Add `NumberDataPointSnapshot`, `linesOfCode*` fields |
| `Teloscope/ViewModels/MetricsRepository.swift` | Add `OTLPNumberDataPoint` fetch |
| `Teloscope/Views/Metrics/MetricsView.swift` | Add widget + notification |
| `Teloscope/Localizable.xcstrings` | Add "Lines of Code" key |
| `TeloscopeTests/Models/OTLPNumberDataPointTests.swift` | **New** — model init test |
| `TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift` | Add metric parsing test |
| `TeloscopeTests/ViewModels/MetricsSummaryTests.swift` | Add lines_of_code tests |

---

## Verification

1. Build the app — `xcodebuild build`
2. Run all tests — `xcodebuild test -scheme Teloscope`
3. Send a test OTLP metric payload to `localhost:<port>/v1/metrics` with `claude_code.lines_of_code.count` data points
4. Open MetricsView and confirm the "Lines of Code" widget appears with correct total
5. If the test payload includes dimensional attributes, confirm breakdown rows appear
