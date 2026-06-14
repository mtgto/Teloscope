# Metrics Visualization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MetricsView に `claude_code.lines_of_code.count` の合計（Added/Removed 内訳付き）を表示する StatWidget を追加する。OTLP メトリクスを `MetricAttribute` / `MetricDataPoint` の二層モデルでパースして SwiftData に保存し、将来的なメトリクス追加（コミット数、PR数など）に対応できるアーキテクチャを構築する。

**Architecture:** `OTLPSpan` / `SpanAttribute` と同じパターンで `MetricDataPoint` / `MetricAttribute` の親子モデルを作成する。受信した OTLP メトリクス protobuf を `ingestMetrics()` でパースし、属性は `MetricAttribute`（key/value 文字列）として保存する。`MetricsSummary` はスナップショット経由でオフメインスレッドで集計し、`MetricsView` の StatWidget で表示する。

**Tech Stack:** Swift, SwiftData, SwiftUI, Swift Testing, SwiftProtobuf（既存生成コード）

---

## 参照すべき既存コード

実装前に以下のファイルを必ず読むこと（パターン理解のため）:

- `Teloscope/Models/Span.swift` — `OTLPSpan` と `SpanAttribute` の定義（MetricDataPoint/MetricAttribute のモデルにする）
- `Teloscope/Ingestion/OTLPIngestionService.swift` — `ingestLogs()` と `ingestTraces()` の実装パターン
- `Teloscope/ViewModels/MetricsSummary.swift` — `SpanSnapshot` / `LogEventSnapshot` / `MetricsSummary.init` の全体構造
- `Teloscope/ViewModels/MetricsRepository.swift` — `computeSummary()` のフェッチパターン
- `Teloscope/Views/Metrics/MetricsView.swift` — `sessionsWidget` / `tokensWidget` などの既存ウィジェット実装
- `TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift` — `makeContainer()` と既存テストの構造

---

## ファイル構成

| ファイル | 変更種別 | 内容 |
|---|---|---|
| `Teloscope/Models/MetricAttribute.swift` | 新規 | 属性1件を表す SwiftData モデル |
| `Teloscope/Models/MetricDataPoint.swift` | 新規 | 数値データポイントを表す SwiftData モデル（MetricAttribute との親子） |
| `Teloscope/Models/ResourceMetrics.swift` | 修正 | コメント更新（raw data 保持の説明を現状に合わせる） |
| `Teloscope/Ingestion/OTLPIngestionService.swift` | 修正 | `ingestMetrics()` を実装、`.otlpMetricsIngested` 通知を追加 |
| `Teloscope/ViewModels/MetricsSummary.swift` | 修正 | `NumberDataPointSnapshot` 追加、`linesOfCodeAdded`/`linesOfCodeRemoved` 追加 |
| `Teloscope/ViewModels/MetricsRepository.swift` | 修正 | `MetricDataPoint` フェッチを追加 |
| `Teloscope/Views/Metrics/MetricsView.swift` | 修正 | `linesOfCodeWidget` 追加、`.otlpMetricsIngested` 通知購読追加 |
| `Teloscope/TeloscopeApp.swift` | 修正 | `MetricAttribute.self` / `MetricDataPoint.self` を Schema に追加 |
| `Teloscope/Localizable.xcstrings` | 修正 | "Lines of Code" / "Added" / "Removed" の日本語訳を追加 |
| `TeloscopeTests/Models/MetricDataPointTests.swift` | 新規 | モデルのテスト |
| `TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift` | 修正 | `makeContainer()` 更新、メトリクス受信テスト追加 |
| `TeloscopeTests/ViewModels/MetricsSummaryTests.swift` | 修正 | `linesOfCode*` 集計テスト追加 |

---

### Task 1: MetricAttribute と MetricDataPoint モデルを作成する

**Files:**
- Create: `Teloscope/Models/MetricAttribute.swift`
- Create: `Teloscope/Models/MetricDataPoint.swift`
- Create: `TeloscopeTests/Models/MetricDataPointTests.swift`

- [ ] **Step 1: テストを書く**

```swift
// TeloscopeTests/Models/MetricDataPointTests.swift
// SPDX-License-Identifier: MIT
import Testing
import Foundation
@testable import Teloscope

struct MetricDataPointTests {
    @Test func initStoresAllFields() {
        let ts = Date(timeIntervalSince1970: 1_000)
        let attr = MetricAttribute(key: "type", value: "added")
        let dp = MetricDataPoint(
            metricName: "claude_code.lines_of_code.count",
            metricUnit: "{lines}",
            timestamp: ts,
            value: 42.0,
            attributes: [attr]
        )
        #expect(dp.metricName == "claude_code.lines_of_code.count")
        #expect(dp.metricUnit == "{lines}")
        #expect(dp.timestamp == ts)
        #expect(dp.value == 42.0)
        #expect(dp.attributes.count == 1)
        #expect(dp.attributes[0].key == "type")
        #expect(dp.attributes[0].value == "added")
    }

    @Test func initWithNoAttributes() {
        let dp = MetricDataPoint(
            metricName: "claude_code.commits",
            metricUnit: "{commits}",
            timestamp: Date(),
            value: 3.0,
            attributes: []
        )
        #expect(dp.attributes.isEmpty)
    }
}
```

- [ ] **Step 2: テストを実行して失敗を確認する**

```
xcodebuild test -scheme Teloscope -testPlan Default \
  -only-testing "TeloscopeTests/MetricDataPointTests" 2>&1 | tail -5
```

Expected: `error: cannot find type 'MetricAttribute'`

- [ ] **Step 3: MetricAttribute モデルを実装する**

```swift
// Teloscope/Models/MetricAttribute.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@Model
final class MetricAttribute {
    var key: String
    var value: String

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}
```

- [ ] **Step 4: MetricDataPoint モデルを実装する**

```swift
// Teloscope/Models/MetricDataPoint.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@Model
final class MetricDataPoint {
    var metricName: String
    var metricUnit: String
    var timestamp: Date
    var value: Double
    @Relationship(deleteRule: .cascade) var attributes: [MetricAttribute]

    init(
        metricName: String,
        metricUnit: String,
        timestamp: Date,
        value: Double,
        attributes: [MetricAttribute] = []
    ) {
        self.metricName = metricName
        self.metricUnit = metricUnit
        self.timestamp = timestamp
        self.value = value
        self.attributes = attributes
    }
}
```

- [ ] **Step 5: テストを実行して成功を確認する**

```
xcodebuild test -scheme Teloscope -testPlan Default \
  -only-testing "TeloscopeTests/MetricDataPointTests" 2>&1 | tail -5
```

Expected: `Test Suite 'MetricDataPointTests' passed`

- [ ] **Step 6: コミット**

```bash
git add Teloscope/Models/MetricAttribute.swift \
        Teloscope/Models/MetricDataPoint.swift \
        TeloscopeTests/Models/MetricDataPointTests.swift
git commit -m "feat: add MetricAttribute and MetricDataPoint SwiftData models"
```

---

### Task 2: メトリクス受信処理を実装する

**Files:**
- Modify: `Teloscope/Ingestion/OTLPIngestionService.swift`
- Modify: `TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift`

- [ ] **Step 1: `makeContainer()` を更新してテストを追加する**

`TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift` の `makeContainer()` に `MetricAttribute.self, MetricDataPoint.self` を追加し、以下のテストを追記する:

```swift
// makeContainer() を以下に置き換える
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
        ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self, LogEvent.self,
        MetricAttribute.self, MetricDataPoint.self,
        configurations: config
    )
}

// 以下のテストを追加する
@Test func ingestsMetricDataPointsFromSumMetric() throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let service = OTLPIngestionService(modelContext: context)

    var dp = Opentelemetry_Proto_Metrics_V1_NumberDataPoint()
    dp.timeUnixNano = 2_000_000_000
    dp.asInt = 50
    var typeAttr = Opentelemetry_Proto_Common_V1_KeyValue()
    typeAttr.key = "type"
    typeAttr.value.stringValue = "added"
    dp.attributes = [typeAttr]

    var sum = Opentelemetry_Proto_Metrics_V1_Sum()
    sum.dataPoints = [dp]

    var metric = Opentelemetry_Proto_Metrics_V1_Metric()
    metric.name = "claude_code.lines_of_code.count"
    metric.unit = "{lines}"
    metric.sum = sum

    var sm = Opentelemetry_Proto_Metrics_V1_ScopeMetrics()
    sm.metrics = [metric]

    var rm = Opentelemetry_Proto_Metrics_V1_ResourceMetrics()
    rm.scopeMetrics = [sm]

    var request = Opentelemetry_Proto_Collector_Metrics_V1_ExportMetricsServiceRequest()
    request.resourceMetrics = [rm]

    service.ingest(.metrics(try request.serializedData()))

    let fetched = try context.fetch(FetchDescriptor<MetricDataPoint>())
    #expect(fetched.count == 1)
    #expect(fetched[0].metricName == "claude_code.lines_of_code.count")
    #expect(fetched[0].metricUnit == "{lines}")
    #expect(fetched[0].value == 50.0)
    #expect(fetched[0].timestamp == Date(timeIntervalSince1970: 2.0))
    #expect(fetched[0].attributes.count == 1)
    #expect(fetched[0].attributes[0].key == "type")
    #expect(fetched[0].attributes[0].value == "added")
}

@Test func ingestsMetricDataPointsFromGaugeMetric() throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let service = OTLPIngestionService(modelContext: context)

    var dp = Opentelemetry_Proto_Metrics_V1_NumberDataPoint()
    dp.timeUnixNano = 1_000_000_000
    dp.asDouble = 3.14

    var gauge = Opentelemetry_Proto_Metrics_V1_Gauge()
    gauge.dataPoints = [dp]

    var metric = Opentelemetry_Proto_Metrics_V1_Metric()
    metric.name = "some.gauge"
    metric.gauge = gauge

    var sm = Opentelemetry_Proto_Metrics_V1_ScopeMetrics()
    sm.metrics = [metric]

    var rm = Opentelemetry_Proto_Metrics_V1_ResourceMetrics()
    rm.scopeMetrics = [sm]

    var request = Opentelemetry_Proto_Collector_Metrics_V1_ExportMetricsServiceRequest()
    request.resourceMetrics = [rm]

    service.ingest(.metrics(try request.serializedData()))

    let fetched = try context.fetch(FetchDescriptor<MetricDataPoint>())
    #expect(fetched.count == 1)
    #expect(fetched[0].metricName == "some.gauge")
    #expect(fetched[0].value == 3.14)
    #expect(fetched[0].attributes.isEmpty)
}

@Test func deletesMetricsOlderThanRetentionDays() throws {
    let container = try makeContainer()
    let context = ModelContext(container)
    let service = OTLPIngestionService(modelContext: context)

    context.insert(MetricDataPoint(
        metricName: "claude_code.lines_of_code.count",
        metricUnit: "{lines}",
        timestamp: Date(timeIntervalSinceNow: -10 * 86400),
        value: 50,
        attributes: []
    ))
    context.insert(MetricDataPoint(
        metricName: "claude_code.lines_of_code.count",
        metricUnit: "{lines}",
        timestamp: Date(timeIntervalSinceNow: -1 * 86400),
        value: 20,
        attributes: []
    ))
    try context.save()

    service.deleteOldData(retentionDays: 7)

    let remaining = try context.fetch(FetchDescriptor<MetricDataPoint>())
    #expect(remaining.count == 1)
    #expect(remaining[0].value == 20.0)
}
```

- [ ] **Step 2: テストを実行して失敗を確認する**

```
xcodebuild test -scheme Teloscope -testPlan Default \
  -only-testing "TeloscopeTests/OTLPIngestionServiceTests/ingestsMetricDataPointsFromSumMetric" \
  2>&1 | tail -5
```

Expected: `Expectation failed` (fetched.count == 0)

- [ ] **Step 3: `ingestMetrics()` を実装する**

`OTLPIngestionService.swift` の `ingestMetrics()` を以下に置き換える:

```swift
private func ingestMetrics(_ data: Data) {
    guard let proto = try? Opentelemetry_Proto_Collector_Metrics_V1_ExportMetricsServiceRequest(
        serializedBytes: data
    ) else { return }
    for rmProto in proto.resourceMetrics {
        for smProto in rmProto.scopeMetrics {
            for metric in smProto.metrics {
                let dataPoints: [Opentelemetry_Proto_Metrics_V1_NumberDataPoint]
                switch metric.data {
                case .sum(let sum):     dataPoints = sum.dataPoints
                case .gauge(let gauge): dataPoints = gauge.dataPoints
                default: continue
                }
                for dp in dataPoints {
                    let value: Double
                    switch dp.value {
                    case .asDouble(let d): value = d
                    case .asInt(let i):    value = Double(i)
                    default: continue
                    }
                    let attrs = dp.attributes.compactMap { kv -> MetricAttribute? in
                        let str: String
                        switch kv.value.value {
                        case .stringValue(let s): str = s
                        case .intValue(let i):    str = String(i)
                        case .doubleValue(let d): str = String(d)
                        case .boolValue(let b):   str = String(b)
                        default: return nil
                        }
                        return MetricAttribute(key: kv.key, value: str)
                    }
                    modelContext.insert(MetricDataPoint(
                        metricName: metric.name,
                        metricUnit: metric.unit,
                        timestamp: Date(unixNano: dp.timeUnixNano),
                        value: value,
                        attributes: attrs
                    ))
                }
            }
        }
    }
    try? modelContext.save()
    NotificationCenter.default.post(name: .otlpMetricsIngested, object: nil)
}
```

- [ ] **Step 4: `.otlpMetricsIngested` を `Notification.Name` extension に追加する**

同ファイルの `// MARK: - Notifications` セクションを以下に更新する:

```swift
extension Notification.Name {
    static let otlpSpansIngested   = Notification.Name("com.teloscope.otlpSpansIngested")
    static let otlpLogsIngested    = Notification.Name("com.teloscope.otlpLogsIngested")
    static let otlpMetricsIngested = Notification.Name("com.teloscope.otlpMetricsIngested")
}
```

- [ ] **Step 5: `deleteOldData()` に MetricDataPoint の削除を追加する**

`deleteOldData()` の OTLPSpan 削除の直後に追加する:

```swift
let metricPredicate = #Predicate<MetricDataPoint> { $0.timestamp < cutoff }
try? modelContext.delete(model: MetricDataPoint.self, where: metricPredicate)
```

- [ ] **Step 6: テストを実行して成功を確認する**

```
xcodebuild test -scheme Teloscope -testPlan Default \
  -only-testing "TeloscopeTests/OTLPIngestionServiceTests" 2>&1 | tail -10
```

Expected: `Test Suite 'OTLPIngestionServiceTests' passed`

- [ ] **Step 7: コミット**

```bash
git add Teloscope/Ingestion/OTLPIngestionService.swift \
        TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift
git commit -m "feat: parse OTLP metrics into MetricDataPoint and MetricAttribute SwiftData records"
```

---

### Task 3: MetricsSummary に数値データポイントの集計を追加する

**Files:**
- Modify: `Teloscope/ViewModels/MetricsSummary.swift`
- Modify: `TeloscopeTests/ViewModels/MetricsSummaryTests.swift`

- [ ] **Step 1: テストを書く**

`TeloscopeTests/ViewModels/MetricsSummaryTests.swift` に以下を追加する:

```swift
// MARK: - linesOfCode

private func ndp(_ type: String, value: Double) -> NumberDataPointSnapshot {
    let attr = MetricAttribute(key: "type", value: type)
    return NumberDataPointSnapshot(MetricDataPoint(
        metricName: "claude_code.lines_of_code.count",
        metricUnit: "{lines}",
        timestamp: Date(),
        value: value,
        attributes: [attr]
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
    let other = NumberDataPointSnapshot(MetricDataPoint(
        metricName: "other.metric", metricUnit: "",
        timestamp: Date(), value: 999,
        attributes: [MetricAttribute(key: "type", value: "added")]
    ))
    let summary = MetricsSummary(spans: [], numberDataPoints: [other], dateRange: fullRange)
    #expect(summary.linesOfCodeAdded == 0)
}

@Test func linesOfCodeIgnoresUnknownType() {
    let points = [ndp("added", value: 10), ndp("unknown_type", value: 999)]
    let summary = MetricsSummary(spans: [], numberDataPoints: points, dateRange: fullRange)
    #expect(summary.linesOfCodeAdded == 10)
    #expect(summary.linesOfCodeRemoved == 0)
}
```

- [ ] **Step 2: テストを実行して失敗を確認する**

```
xcodebuild test -scheme Teloscope -testPlan Default \
  -only-testing "TeloscopeTests/MetricsSummaryTests/linesOfCodeSumsAddedAndRemoved" \
  2>&1 | tail -5
```

Expected: `error: cannot find 'NumberDataPointSnapshot'`

- [ ] **Step 3: `NumberDataPointSnapshot` を追加する**

`MetricsSummary.swift` の `LogEventSnapshot` struct の直後に追加する:

```swift
struct NumberDataPointSnapshot: Sendable {
    let metricName: String
    let timestamp: Date
    let value: Double
    let attributes: [String: String]

    init(_ point: MetricDataPoint) {
        metricName = point.metricName
        timestamp = point.timestamp
        value = point.value
        attributes = Dictionary(
            point.attributes.map { ($0.key, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
```

- [ ] **Step 4: `MetricsSummary` に stored properties を追加する**

`MetricsSummary` の `hourlyRequests` プロパティの直後に追加する:

```swift
let linesOfCodeAdded: Int64
let linesOfCodeRemoved: Int64
```

- [ ] **Step 5: `init` シグネチャを更新する**

```swift
init(spans: [SpanSnapshot], logEvents: [LogEventSnapshot] = [], numberDataPoints: [NumberDataPointSnapshot] = [], dateRange: DateInterval) {
```

- [ ] **Step 6: `init` 末尾に集計ロジックを追加する**

`self.claudeSkillRanking = sort(claudeSkillCounts)` の直後に追加する:

```swift
var linesAdded: Int64 = 0
var linesRemoved: Int64 = 0
for dp in numberDataPoints where dp.metricName == "claude_code.lines_of_code.count" {
    switch dp.attributes["type"] {
    case "added":   linesAdded   += Int64(dp.value)
    case "removed": linesRemoved += Int64(dp.value)
    default: break
    }
}
self.linesOfCodeAdded   = linesAdded
self.linesOfCodeRemoved = linesRemoved
```

- [ ] **Step 7: テストを実行して成功を確認する**

```
xcodebuild test -scheme Teloscope -testPlan Default \
  -only-testing "TeloscopeTests/MetricsSummaryTests" 2>&1 | tail -10
```

Expected: `Test Suite 'MetricsSummaryTests' passed`

- [ ] **Step 8: コミット**

```bash
git add Teloscope/ViewModels/MetricsSummary.swift \
        TeloscopeTests/ViewModels/MetricsSummaryTests.swift
git commit -m "feat: aggregate lines_of_code added/removed in MetricsSummary"
```

---

### Task 4: MetricsRepository で MetricDataPoint をフェッチする

**Files:**
- Modify: `Teloscope/ViewModels/MetricsRepository.swift`

- [ ] **Step 1: `computeSummary` を更新する**

`logEvents` フェッチの直後、`return` 文の前に追加する:

```swift
let metricDescriptor = FetchDescriptor<MetricDataPoint>(
    predicate: #Predicate { $0.timestamp >= start && $0.timestamp <= end }
)
let numberDataPoints = try modelContext.fetch(metricDescriptor).map { NumberDataPointSnapshot($0) }
```

`return` 文を変更する:

```swift
return (availableModels, MetricsSummary(spans: filtered, logEvents: logEvents, numberDataPoints: numberDataPoints, dateRange: dateRange))
```

- [ ] **Step 2: ビルドが通ることを確認する**

```
xcodebuild build -scheme Teloscope 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 3: コミット**

```bash
git add Teloscope/ViewModels/MetricsRepository.swift
git commit -m "feat: fetch MetricDataPoint in MetricsRepository and pass to MetricsSummary"
```

---

### Task 5: MetricsView にウィジェットを追加し、ローカライズする

**Files:**
- Modify: `Teloscope/Views/Metrics/MetricsView.swift`
- Modify: `Teloscope/Localizable.xcstrings`

- [ ] **Step 1: `linesOfCodeWidget` メソッドを追加する**

`sessionsWidget` メソッドの直後に追加する:

```swift
private func linesOfCodeWidget(_ m: MetricsSummary?) -> some View {
    let total = m.map { $0.linesOfCodeAdded + $0.linesOfCodeRemoved }
    return StatWidgetView(
        title: "Lines of Code",
        primaryValue: total?.formatted(.number) ?? "000",
        rows: [
            (label: "Added",   value: m?.linesOfCodeAdded.formatted(.number)   ?? "000"),
            (label: "Removed", value: m?.linesOfCodeRemoved.formatted(.number) ?? "000"),
        ]
    )
}
```

- [ ] **Step 2: `metricsGrid` に追加する**

`sessionsWidget(m)` の直後、`approvalWidget(m)` の前に挿入する:

```swift
sessionsWidget(m)
linesOfCodeWidget(m)
approvalWidget(m)
```

- [ ] **Step 3: `.otlpMetricsIngested` 通知を購読する**

`body` の `.otlpLogsIngested` task の直後に追加する:

```swift
.task {
    for await _ in NotificationCenter.default.notifications(named: .otlpMetricsIngested) {
        refresh()
    }
}
```

- [ ] **Step 4: `#Preview` の modelContainer に追加する**

```swift
.modelContainer(
    for: [ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
          ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self,
          MetricAttribute.self, MetricDataPoint.self],
    inMemory: true
)
```

- [ ] **Step 5: `Localizable.xcstrings` にキーを追加する**

既存エントリのアルファベット順の正しい位置に挿入する（`grep -n '"A\|"L\|"R"' Teloscope/Localizable.xcstrings` で位置を確認してから編集する）:

```json
"Added" : {
  "localizations" : {
    "ja" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "追加"
      }
    }
  }
},
```

```json
"Lines of Code" : {
  "localizations" : {
    "ja" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "コード行数"
      }
    }
  }
},
```

```json
"Removed" : {
  "localizations" : {
    "ja" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "削除"
      }
    }
  }
},
```

- [ ] **Step 6: ビルドが通ることを確認する**

```
xcodebuild build -scheme Teloscope 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

- [ ] **Step 7: コミット**

```bash
git add Teloscope/Views/Metrics/MetricsView.swift Teloscope/Localizable.xcstrings
git commit -m "feat: add Lines of Code widget to MetricsView"
```

---

### Task 6: アプリスキーマ登録・データ削除・コメント更新

**Files:**
- Modify: `Teloscope/TeloscopeApp.swift`
- Modify: `Teloscope/Models/ResourceMetrics.swift`

- [ ] **Step 1: `TeloscopeApp` の Schema に追加する**

`sharedModelContainer` の `Schema([...])` 配列に追加する:

```swift
let schema = Schema([
    ResourceSpans.self,
    ScopeSpans.self,
    OTLPSpan.self,
    SpanAttribute.self,
    ResourceAttribute.self,
    ResourceMetrics.self,
    ResourceLogs.self,
    LogEvent.self,
    MetricAttribute.self,
    MetricDataPoint.self,
])
```

- [ ] **Step 2: `ResourceMetrics.swift` のコメントを更新する**

```swift
/// Raw metrics payload kept for reference. Parsed numeric data points are stored in MetricDataPoint.
```

- [ ] **Step 3: 全テストを実行して成功を確認する**

```
xcodebuild test -scheme Teloscope -testPlan Default 2>&1 | tail -10
```

Expected: `Test Suite 'All tests' passed`

- [ ] **Step 4: コミット**

```bash
git add Teloscope/TeloscopeApp.swift Teloscope/Models/ResourceMetrics.swift
git commit -m "chore: register MetricAttribute and MetricDataPoint in app schema"
```

---

## 動作確認

1. アプリをビルドして起動する
2. Claude Code でファイル編集を行い、Teloscope にメトリクスを送信させる
3. MetricsView の「Lines of Code」ウィジェットに Added / Removed の値が表示されることを確認する
4. SQLite で直接確認する:

```
sqlite3 ~/Library/Containers/net.mtgto.Teloscope/Data/Library/Application\ Support/default.store \
  "SELECT ZKEY, ZVALUE FROM ZMETRICATTRIBUTE LIMIT 20;"

sqlite3 ~/Library/Containers/net.mtgto.Teloscope/Data/Library/Application\ Support/default.store \
  "SELECT m.ZMETRICNAME, a.ZKEY, a.ZVALUE, m.ZVALUE
   FROM ZMETRICDATAPOINT m
   JOIN ZMETRICATTRIBUTE a ON a.Z_PK IN (
     SELECT Z_3ATTRIBUTES FROM Z_3ATTRIBUTES WHERE Z_3METRICDATAPOINT = m.Z_PK
   )
   WHERE m.ZMETRICNAME = 'claude_code.lines_of_code.count' LIMIT 10;"
```

> **Note:** SwiftData の多対一リレーションシップの結合テーブル名は実際のスキーマで `.tables` で確認してから使うこと。

---

## 参考: Draft PR #4

`feat/metrics` ブランチ（Draft PR #4）に前回の実装がある。`attributesJSON` 方式から `MetricAttribute` 方式への変更点、テストの構造、protobuf の型名などを参照として使える。ただし `attributesJSON` を使っているコードは今回の実装では使わない。
