# Skill Ranking View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MetricsダッシュボードにSkill使用ランキングウィジェットを追加する（`claude_code.skill_activated` OTELログイベントを解析して集計）。

**Architecture:** OTLPログのprotobufを解析して`skill_activated`イベントを`LogEvent` SwiftDataモデルに保存する。`MetricsSummary`に`skillRanking`プロパティを追加し、`MetricsRepository`経由で`MetricsView`に表示する。

**Tech Stack:** Swift, SwiftData, SwiftProtobuf, Swift Charts, Swift Testing

---

## File Map

| Action   | File                                                                    | Responsibility                                                  |
|----------|-------------------------------------------------------------------------|-----------------------------------------------------------------|
| Create   | `Teloscope/Models/LogEvent.swift`                                       | SwiftData model for parsed log events (skill_activated)         |
| Modify   | `Teloscope/Ingestion/OTLPIngestionService.swift`                        | Parse skill_activated from OTLP logs protobuf                   |
| Modify   | `Teloscope/ViewModels/MetricsSummary.swift`                             | Add LogEventSnapshot struct + skillRanking computation          |
| Modify   | `Teloscope/ViewModels/MetricsRepository.swift`                          | Fetch LogEvent records and pass to MetricsSummary               |
| Modify   | `Teloscope/Views/Metrics/MetricsView.swift`                             | Add skillRankingWidget + listen to otlpLogsIngested             |
| Modify   | `Teloscope/TeloscopeApp.swift`                                          | Add LogEvent.self to schema                                     |
| Modify   | `Teloscope/Localizable.xcstrings`                                       | Add "Skill Usage" Japanese translation                          |
| Modify   | `TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift`              | Add log ingestion tests + update makeContainer                  |
| Modify   | `TeloscopeTests/ViewModels/MetricsSummaryTests.swift`                   | Add skillRanking tests                                          |
| Modify   | `TeloscopeTests/ViewModels/MetricsRepositoryTests.swift`                | Update makeContainer + add skill repository test                |
| Modify   | `TeloscopeTests/ViewModels/MetricsDashboardModelTests.swift`            | Update makeContainer                                            |
| Modify   | `TeloscopeTests/VRT/PreviewSnapshotTests.swift`                         | Update ModelContainer calls (2 places, lines ~350, ~366)        |

---

### Task 1: LogEvent SwiftData Model

**Files:**
- Create: `Teloscope/Models/LogEvent.swift`
- Modify: `Teloscope/TeloscopeApp.swift`
- Modify: `TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift` (makeContainer only)
- Modify: `TeloscopeTests/ViewModels/MetricsRepositoryTests.swift` (makeContainer only)
- Modify: `TeloscopeTests/ViewModels/MetricsDashboardModelTests.swift` (makeContainer only)
- Modify: `TeloscopeTests/VRT/PreviewSnapshotTests.swift` (2 ModelContainer calls)

- [ ] **Step 1: Write failing test**

`TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift` の既存 `makeContainer()` を更新する前に、まず下記テストを追加して `LogEvent.self` がないためビルドエラーになることを確認する。

```swift
@Test func logEventCanBeInserted() throws {
    let container = try makeContainer()
    let ctx = ModelContext(container)
    let event = LogEvent(
        eventName: "skill_activated",
        timestamp: Date(),
        sessionId: "sess-1",
        skillName: "superpowers:brainstorming",
        invocationTrigger: "claude-proactive",
        skillSource: "userSettings"
    )
    ctx.insert(event)
    try ctx.save()
    let fetched = try ctx.fetch(FetchDescriptor<LogEvent>())
    #expect(fetched.count == 1)
    #expect(fetched[0].skillName == "superpowers:brainstorming")
}
```

- [ ] **Step 2: Implement LogEvent model**

Create `Teloscope/Models/LogEvent.swift`:

```swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@Model
final class LogEvent {
    var eventName: String
    var timestamp: Date
    var sessionId: String?
    var skillName: String?
    var invocationTrigger: String?
    var skillSource: String?

    init(
        eventName: String,
        timestamp: Date,
        sessionId: String? = nil,
        skillName: String? = nil,
        invocationTrigger: String? = nil,
        skillSource: String? = nil
    ) {
        self.eventName = eventName
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.skillName = skillName
        self.invocationTrigger = invocationTrigger
        self.skillSource = skillSource
    }
}
```

- [ ] **Step 3: Add LogEvent to TeloscopeApp schema**

`Teloscope/TeloscopeApp.swift` の `schema` 定義に `LogEvent.self` を追加:

```swift
let schema = Schema([
    ResourceSpans.self,
    ScopeSpans.self,
    OTLPSpan.self,
    SpanAttribute.self,
    ResourceAttribute.self,
    ResourceMetrics.self,
    ResourceLogs.self,
    LogEvent.self,   // add this line
])
```

- [ ] **Step 4: Update all test makeContainer() helpers**

下記4ファイルすべての `makeContainer()` / `ModelContainer(for:...)` に `LogEvent.self` を追加する。

`TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift`:
```swift
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
        ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self, LogEvent.self,
        configurations: config
    )
}
```

`TeloscopeTests/ViewModels/MetricsRepositoryTests.swift`:
```swift
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
             ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self, LogEvent.self,
        configurations: config
    )
}
```

`TeloscopeTests/ViewModels/MetricsDashboardModelTests.swift` (top-level function):
```swift
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: ResourceSpans.self, ScopeSpans.self, OTLPSpan.self, SpanAttribute.self,
             ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self, LogEvent.self,
        configurations: config
    )
}
```

`TeloscopeTests/VRT/PreviewSnapshotTests.swift` の2箇所（約350行目・366行目）の `ModelContainer(for:...)` にも同様に `LogEvent.self` を追加する。

- [ ] **Step 5: Run tests and confirm pass**

```bash
cd /Users/user/work/cocoa/Teloscope
xcodebuild test -scheme Teloscope -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `logEventCanBeInserted` が PASS、他のテストも引き続き PASS。

- [ ] **Step 6: Commit**

```bash
git add Teloscope/Models/LogEvent.swift \
        Teloscope/TeloscopeApp.swift \
        TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift \
        TeloscopeTests/ViewModels/MetricsRepositoryTests.swift \
        TeloscopeTests/ViewModels/MetricsDashboardModelTests.swift \
        TeloscopeTests/VRT/PreviewSnapshotTests.swift
git commit -m "feat: add LogEvent SwiftData model for parsed OTLP log events"
```

---

### Task 2: Parse skill_activated from OTLP Logs

**Files:**
- Modify: `Teloscope/Ingestion/OTLPIngestionService.swift`
- Modify: `TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift`

- [ ] **Step 1: Write failing tests**

`TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift` に追加:

```swift
// MARK: - Log ingestion helpers

private func makeLogRequest(
    eventName: String,
    sessionId: String? = nil,
    skillName: String? = nil,
    invocationTrigger: String? = nil,
    skillSource: String? = nil,
    timeUnixNano: UInt64 = 1_000_000_000
) throws -> Data {
    func kv(_ key: String, _ value: String) -> Opentelemetry_Proto_Common_V1_KeyValue {
        var kv = Opentelemetry_Proto_Common_V1_KeyValue()
        kv.key = key; kv.value.stringValue = value; return kv
    }
    var logRecord = Opentelemetry_Proto_Logs_V1_LogRecord()
    logRecord.timeUnixNano = timeUnixNano
    var attrs = [kv("event.name", eventName)]
    if let v = sessionId         { attrs.append(kv("session.id", v)) }
    if let v = skillName         { attrs.append(kv("skill.name", v)) }
    if let v = invocationTrigger { attrs.append(kv("invocation_trigger", v)) }
    if let v = skillSource       { attrs.append(kv("skill.source", v)) }
    logRecord.attributes = attrs

    var scopeLogs = Opentelemetry_Proto_Logs_V1_ScopeLogs()
    scopeLogs.logRecords = [logRecord]
    var resourceLogs = Opentelemetry_Proto_Logs_V1_ResourceLogs()
    resourceLogs.scopeLogs = [scopeLogs]
    var request = Opentelemetry_Proto_Collector_Logs_V1_ExportLogsServiceRequest()
    request.resourceLogs = [resourceLogs]
    return try request.serializedData()
}

@Test func ingestsSkillActivatedLogEvent() throws {
    let container = try makeContainer()
    let ctx = ModelContext(container)
    let service = OTLPIngestionService(modelContext: ctx)

    let data = try makeLogRequest(
        eventName: "skill_activated",
        sessionId: "sess-abc",
        skillName: "superpowers:brainstorming",
        invocationTrigger: "claude-proactive",
        skillSource: "userSettings"
    )
    service.ingest(.logs(data))

    let events = try ctx.fetch(FetchDescriptor<LogEvent>())
    #expect(events.count == 1)
    #expect(events[0].eventName == "skill_activated")
    #expect(events[0].sessionId == "sess-abc")
    #expect(events[0].skillName == "superpowers:brainstorming")
    #expect(events[0].invocationTrigger == "claude-proactive")
    #expect(events[0].skillSource == "userSettings")
}

@Test func ignoresNonSkillActivatedLogEvents() throws {
    let container = try makeContainer()
    let ctx = ModelContext(container)
    let service = OTLPIngestionService(modelContext: ctx)

    let data = try makeLogRequest(eventName: "api_request")
    service.ingest(.logs(data))

    let events = try ctx.fetch(FetchDescriptor<LogEvent>())
    #expect(events.isEmpty)
}

@Test func ingestLogsPostsOtlpLogsIngestedNotification() throws {
    let container = try makeContainer()
    let ctx = ModelContext(container)
    let service = OTLPIngestionService(modelContext: ctx)

    var notified = false
    let token = NotificationCenter.default.addObserver(
        forName: .otlpLogsIngested, object: nil, queue: .main
    ) { _ in notified = true }
    defer { NotificationCenter.default.removeObserver(token) }

    let data = try makeLogRequest(eventName: "skill_activated")
    service.ingest(.logs(data))
    #expect(notified)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Teloscope -destination 'platform=macOS' \
  -only-testing TeloscopeTests/OTLPIngestionServiceTests 2>&1 | tail -20
```

Expected: 3テストが FAIL（`LogEvent` の挿入処理・`otlpLogsIngested` 通知が未実装のため）。

- [ ] **Step 3: Implement ingestLogs() parsing**

`Teloscope/Ingestion/OTLPIngestionService.swift` の `ingestLogs(_:)` を置き換え、`Notification.Name` 拡張に `otlpLogsIngested` を追加:

```swift
private func ingestLogs(_ data: Data) {
    guard let proto = try? Opentelemetry_Proto_Collector_Logs_V1_ExportLogsServiceRequest(
        serializedBytes: data
    ) else { return }
    modelContext.insert(ResourceLogs(rawData: data))
    for rlProto in proto.resourceLogs {
        for slProto in rlProto.scopeLogs {
            for lrProto in slProto.logRecords {
                let attrs = Dictionary(
                    lrProto.attributes.map { ($0.key, AttributeValue(anyValue: $0.value)) },
                    uniquingKeysWith: { first, _ in first }
                )
                guard attrs["event.name"]?.stringValue == "skill_activated" else { continue }
                let nano = lrProto.timeUnixNano > 0
                    ? lrProto.timeUnixNano
                    : lrProto.observedTimeUnixNano
                modelContext.insert(LogEvent(
                    eventName: "skill_activated",
                    timestamp: Date(unixNano: nano),
                    sessionId: attrs["session.id"]?.stringValue,
                    skillName: attrs["skill.name"]?.stringValue,
                    invocationTrigger: attrs["invocation_trigger"]?.stringValue,
                    skillSource: attrs["skill.source"]?.stringValue
                ))
            }
        }
    }
    try? modelContext.save()
    NotificationCenter.default.post(name: .otlpLogsIngested, object: nil)
}
```

`Notification.Name` 拡張（`OTLPIngestionService.swift` の末尾付近）に追加:

```swift
static let otlpLogsIngested = Notification.Name("com.teloscope.otlpLogsIngested")
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme Teloscope -destination 'platform=macOS' \
  -only-testing TeloscopeTests/OTLPIngestionServiceTests 2>&1 | tail -20
```

Expected: 3テストが PASS。

- [ ] **Step 5: Commit**

```bash
git add Teloscope/Ingestion/OTLPIngestionService.swift \
        TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift
git commit -m "feat: parse skill_activated log events in OTLPIngestionService"
```

---

### Task 3: LogEventSnapshot + MetricsSummary.skillRanking

**Files:**
- Modify: `Teloscope/ViewModels/MetricsSummary.swift`
- Modify: `TeloscopeTests/ViewModels/MetricsSummaryTests.swift`

- [ ] **Step 1: Write failing tests**

`TeloscopeTests/ViewModels/MetricsSummaryTests.swift` に追加:

```swift
// MARK: - Helpers for LogEvent

private func logSnap(
    skillName: String?,
    at date: Date = Date()
) -> LogEventSnapshot {
    LogEventSnapshot(LogEvent(
        eventName: "skill_activated",
        timestamp: date,
        skillName: skillName
    ))
}

// MARK: - skillRanking

@Test func skillRankingCountsSkillEvents() {
    let events = [
        logSnap(skillName: "superpowers:brainstorming"),
        logSnap(skillName: "superpowers:brainstorming"),
        logSnap(skillName: "update-config"),
    ]
    let summary = MetricsSummary(spans: [], logEvents: events, dateRange: fullRange)
    #expect(summary.skillRanking.count == 2)
    #expect(summary.skillRanking[0] == (name: "superpowers:brainstorming", count: 2))
    #expect(summary.skillRanking[1] == (name: "update-config", count: 1))
}

@Test func skillRankingIgnoresNilSkillName() {
    let events = [
        logSnap(skillName: "superpowers:brainstorming"),
        logSnap(skillName: nil),
    ]
    let summary = MetricsSummary(spans: [], logEvents: events, dateRange: fullRange)
    #expect(summary.skillRanking.count == 1)
    #expect(summary.skillRanking[0].name == "superpowers:brainstorming")
}

@Test func skillRankingIsEmptyWithNoEvents() {
    let summary = MetricsSummary(spans: [], logEvents: [], dateRange: fullRange)
    #expect(summary.skillRanking.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Teloscope -destination 'platform=macOS' \
  -only-testing TeloscopeTests/MetricsSummaryTests 2>&1 | tail -20
```

Expected: `LogEventSnapshot` 型が未定義でビルドエラー。

- [ ] **Step 3: Implement LogEventSnapshot and skillRanking**

`Teloscope/ViewModels/MetricsSummary.swift` の先頭（`SpanSnapshot` の直後）に追加:

```swift
struct LogEventSnapshot: Sendable {
    let eventName: String
    let timestamp: Date
    let sessionId: String?
    let skillName: String?
    let invocationTrigger: String?
    let skillSource: String?

    init(_ event: LogEvent) {
        eventName = event.eventName
        timestamp = event.timestamp
        sessionId = event.sessionId
        skillName = event.skillName
        invocationTrigger = event.invocationTrigger
        skillSource = event.skillSource
    }
}
```

`MetricsSummary` 構造体に `skillRanking` プロパティを追加し、`init` を更新:

```swift
struct MetricsSummary {
    // ... existing properties ...
    let skillRanking: [(name: String, count: Int)]  // add this

    init(spans: [SpanSnapshot], logEvents: [LogEventSnapshot] = [], dateRange: DateInterval) {
        // ... existing computation unchanged ...

        // Compute skillRanking from log events
        var skillCounts: [String: Int] = [:]
        for event in logEvents {
            if let name = event.skillName {
                skillCounts[name, default: 0] += 1
            }
        }
        self.skillRanking = skillCounts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (name: $0.key, count: $0.value) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme Teloscope -destination 'platform=macOS' \
  -only-testing TeloscopeTests/MetricsSummaryTests 2>&1 | tail -20
```

Expected: 新規3テストが PASS、既存テストも引き続き PASS（`logEvents` デフォルト `[]` のため）。

- [ ] **Step 5: Commit**

```bash
git add Teloscope/ViewModels/MetricsSummary.swift \
        TeloscopeTests/ViewModels/MetricsSummaryTests.swift
git commit -m "feat: add LogEventSnapshot and skillRanking to MetricsSummary"
```

---

### Task 4: MetricsRepository Fetches LogEvent

**Files:**
- Modify: `Teloscope/ViewModels/MetricsRepository.swift`
- Modify: `TeloscopeTests/ViewModels/MetricsRepositoryTests.swift`

- [ ] **Step 1: Write failing test**

`TeloscopeTests/ViewModels/MetricsRepositoryTests.swift` に追加:

```swift
@Test func skillRankingIncludesLogEventsInDateRange() async throws {
    let container = try makeContainer()
    let ctx = ModelContext(container)
    ctx.insert(LogEvent(
        eventName: "skill_activated",
        timestamp: now,
        skillName: "superpowers:brainstorming"
    ))
    ctx.insert(LogEvent(
        eventName: "skill_activated",
        timestamp: now.addingTimeInterval(-7200), // outside range
        skillName: "update-config"
    ))
    try ctx.save()

    let repo = MetricsRepository(modelContainer: container)
    let range = DateInterval(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(1))
    let (_, summary) = try await repo.computeSummary(dateRange: range, selectedModels: [])
    #expect(summary.skillRanking.count == 1)
    #expect(summary.skillRanking[0].name == "superpowers:brainstorming")
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme Teloscope -destination 'platform=macOS' \
  -only-testing TeloscopeTests/MetricsRepositoryTests/MetricsRepositoryTests/skillRankingIncludesLogEventsInDateRange 2>&1 | tail -20
```

Expected: FAIL（`skillRanking` が空のため）。

- [ ] **Step 3: Update MetricsRepository.computeSummary**

`Teloscope/ViewModels/MetricsRepository.swift` の `computeSummary` を更新:

```swift
@ModelActor
actor MetricsRepository {
    func computeSummary(
        dateRange: DateInterval,
        selectedModels: Set<String>
    ) throws -> (availableModels: [String], summary: MetricsSummary) {
        let start = dateRange.start
        let end = dateRange.end

        let spanDescriptor = FetchDescriptor<OTLPSpan>(
            predicate: #Predicate { $0.startTime >= start && $0.startTime <= end }
        )
        let fetched = try modelContext.fetch(spanDescriptor)
        let dateFiltered = fetched.map { SpanSnapshot($0) }

        let modelSet = Set(dateFiltered.compactMap { snap -> String? in
            guard snap.name.hasPrefix("claude_code.llm_request") else { return nil }
            return snap.model
        })
        let availableModels = modelSet.sorted()

        let filtered: [SpanSnapshot]
        if selectedModels.isEmpty {
            filtered = dateFiltered
        } else {
            filtered = dateFiltered.filter { snap in
                guard snap.name.hasPrefix("claude_code.llm_request") else { return true }
                guard let m = snap.model else { return false }
                return selectedModels.contains(m)
            }
        }

        let logDescriptor = FetchDescriptor<LogEvent>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp <= end }
        )
        let logEvents = try modelContext.fetch(logDescriptor).map { LogEventSnapshot($0) }

        return (availableModels, MetricsSummary(spans: filtered, logEvents: logEvents, dateRange: dateRange))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme Teloscope -destination 'platform=macOS' \
  -only-testing TeloscopeTests/MetricsRepositoryTests 2>&1 | tail -20
```

Expected: 全テストが PASS。

- [ ] **Step 5: Commit**

```bash
git add Teloscope/ViewModels/MetricsRepository.swift \
        TeloscopeTests/ViewModels/MetricsRepositoryTests.swift
git commit -m "feat: fetch LogEvent records in MetricsRepository for skill ranking"
```

---

### Task 5: MetricsView Skill Ranking Widget

**Files:**
- Modify: `Teloscope/Views/Metrics/MetricsView.swift`
- Modify: `Teloscope/Localizable.xcstrings`

- [ ] **Step 1: Add Japanese localization for "Skill Usage"**

`Teloscope/Localizable.xcstrings` に "Tool Usage" と同じパターンで追加（アルファベット順の適切な位置に挿入）:

```json
"Skill Usage" : {
  "localizations" : {
    "ja" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "スキル使用状況"
      }
    }
  }
},
```

- [ ] **Step 2: Add skillRankingWidget to MetricsView**

`Teloscope/Views/Metrics/MetricsView.swift` の `metricsGrid(_:)` に `skillRankingWidget` を追加:

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
            skillRankingWidget(m)   // add this line
            usageHeatmapWidget(m)
            tokensTimelineWidget(m)
            costTimelineWidget(m)
            requestsTimelineWidget(m)
        }
        .padding(12)
    }
}
```

末尾付近に `skillRankingWidget` メソッドを追加（`toolRankingWidget` の直後）:

```swift
private func skillRankingWidget(_ m: MetricsSummary?) -> some View {
    BarWidgetView(
        title: "Skill Usage",
        items: m?.skillRanking ?? []
    )
}
```

- [ ] **Step 3: Listen to otlpLogsIngested notification**

`MetricsView.body` の `.task` ブロックを更新して `otlpLogsIngested` も監視する:

```swift
.task {
    for await _ in NotificationCenter.default.notifications(named: .otlpSpansIngested) {
        refresh()
    }
}
.task {
    for await _ in NotificationCenter.default.notifications(named: .otlpLogsIngested) {
        refresh()
    }
}
```

- [ ] **Step 4: Run full test suite**

```bash
xcodebuild test -scheme Teloscope -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: 全テストが PASS。

- [ ] **Step 5: Commit**

```bash
git add Teloscope/Views/Metrics/MetricsView.swift \
        Teloscope/Localizable.xcstrings
git commit -m "feat: add skill ranking widget to metrics dashboard"
```
