# OTLP Collection & Traces UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** OTLP/HTTP サーバーで Claude Code のテレメトリを受信し SwiftData に保存、Traces をガントチャートで表示する macOS アプリを構築する。

**Architecture:** swift-nio がポート 4318 で HTTP リッスン、OTLPIngestionService が Protobuf デコード → SwiftData 保存、SwiftUI Views が `@Query` で SwiftData を直接参照。サーバー停止中でも蓄積済みデータは閲覧できる。

**Tech Stack:** SwiftUI, SwiftData, swift-nio 2.x (NIO + NIOHTTP1), swift-protobuf, SwiftCharts, macOS 14+

---

## File Map

**作成ファイル:**
- `Teloscope/Models/Span.swift` — `Span`, `SpanAttribute`, `AttributeValue`, `SpanKind`, `SpanStatus`
- `Teloscope/Models/ScopeSpans.swift` — `ScopeSpans`
- `Teloscope/Models/ResourceSpans.swift` — `ResourceSpans`, `ResourceAttribute`
- `Teloscope/Models/ResourceMetrics.swift` — `ResourceMetrics`（rawData保存のみ）
- `Teloscope/Models/ResourceLogs.swift` — `ResourceLogs`（rawData保存のみ）
- `Teloscope/Settings/AppSettings.swift` — `@Observable` UserDefaults ラッパー
- `Teloscope/Server/OTLPRequest.swift` — `enum OTLPRequest`
- `Teloscope/Server/OTLPHTTPHandler.swift` — NIO `ChannelInboundHandler`
- `Teloscope/Server/OTLPServer.swift` — `@Observable` HTTP サーバーライフサイクル
- `Teloscope/Ingestion/OTLPIngestionService.swift` — Protobuf デコード + SwiftData 保存 + retention 削除
- `Teloscope/Views/MainView.swift` — `NavigationSplitView` ルート＋ツールバー
- `Teloscope/Views/Traces/TraceListView.swift` — Trace 一覧テーブル＋ガントチャート上下分割
- `Teloscope/Views/Traces/GanttChartView.swift` — SwiftCharts BarMark ガントチャート
- `Teloscope/Views/Traces/SpanDetailView.swift` — Span 属性ポップオーバー
- `Teloscope/Views/Settings/SettingsView.swift` — 設定画面
- `Teloscope/Generated/` — protoc 生成 Swift ファイル群
- `TeloscopeTests/Models/SpanTests.swift`
- `TeloscopeTests/Settings/AppSettingsTests.swift`
- `TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift`
- `TeloscopeTests/Server/OTLPServerTests.swift`

**変更ファイル:**
- `Teloscope/TeloscopeApp.swift` — `Item` 削除、新モデル・`OTLPServer`・`OTLPIngestionService` 統合
- `Teloscope/ContentView.swift` → `MainView` で置き換え

**削除ファイル:**
- `Teloscope/Item.swift`

---

## Task 1: SwiftData モデル

**Files:**
- Create: `Teloscope/Models/Span.swift`
- Create: `Teloscope/Models/ScopeSpans.swift`
- Create: `Teloscope/Models/ResourceSpans.swift`
- Create: `Teloscope/Models/ResourceMetrics.swift`
- Create: `Teloscope/Models/ResourceLogs.swift`
- Delete: `Teloscope/Item.swift`
- Test: `TeloscopeTests/Models/SpanTests.swift`

- [ ] **Step 1: テストを書く**

```swift
// TeloscopeTests/Models/SpanTests.swift
// SPDX-License-Identifier: MIT
import Testing
import SwiftData
@testable import Teloscope

struct SpanTests {
    @Test func spanCreation() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ResourceSpans.self, ScopeSpans.self, Span.self, SpanAttribute.self,
            ResourceMetrics.self, ResourceLogs.self,
            configurations: config
        )
        let context = ModelContext(container)

        let attr = SpanAttribute(key: "http.method", value: .string("GET"))
        let span = Span(
            traceId: "abc123",
            spanId: "def456",
            parentSpanId: nil,
            name: "GET /api",
            kind: .server,
            startTime: Date(timeIntervalSince1970: 1000),
            endTime: Date(timeIntervalSince1970: 1001),
            status: .ok,
            attributes: [attr]
        )
        context.insert(span)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Span>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "GET /api")
        #expect(fetched[0].kind == .server)
        #expect(fetched[0].status == .ok)
        #expect(fetched[0].parentSpanId == nil)
        #expect(fetched[0].attributes.first?.value == .string("GET"))
    }

    @Test func attributeValueRoundTrip() throws {
        let values: [AttributeValue] = [
            .string("hello"),
            .int64(42),
            .double(3.14),
            .bool(true),
            .stringArray(["a", "b"])
        ]
        for value in values {
            let attr = SpanAttribute(key: "k", value: value)
            #expect(attr.value == value)
        }
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Xcode でテストターゲットをビルドして `SpanTests` が `Span` 未定義でコンパイルエラーになることを確認。

- [ ] **Step 3: モデルを実装する**

```swift
// Teloscope/Models/Span.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

enum AttributeValue: Codable, Equatable {
    case string(String)
    case int64(Int64)
    case double(Double)
    case bool(Bool)
    case stringArray([String])
}

enum SpanKind: Int, Codable {
    case unspecified = 0
    case `internal` = 1
    case server = 2
    case client = 3
    case producer = 4
    case consumer = 5
}

enum SpanStatus: Int, Codable {
    case unset = 0
    case ok = 1
    case error = 2
}

@Model
final class SpanAttribute {
    var key: String
    /// AttributeValue を JSON 文字列として保存（SwiftData は associated-value enum を直接サポートしない）
    var valueJSON: String

    init(key: String, value: AttributeValue) {
        self.key = key
        self.valueJSON = (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? ""
    }

    var value: AttributeValue? {
        guard let data = valueJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AttributeValue.self, from: data)
    }
}

@Model
final class Span {
    var traceId: String
    var spanId: String
    var parentSpanId: String?
    var name: String
    var kindRaw: Int
    var startTime: Date
    var endTime: Date
    var statusRaw: Int
    @Relationship(deleteRule: .cascade)
    var attributes: [SpanAttribute]

    var kind: SpanKind { SpanKind(rawValue: kindRaw) ?? .unspecified }
    var status: SpanStatus { SpanStatus(rawValue: statusRaw) ?? .unset }

    init(
        traceId: String,
        spanId: String,
        parentSpanId: String? = nil,
        name: String,
        kind: SpanKind = .unspecified,
        startTime: Date,
        endTime: Date,
        status: SpanStatus = .unset,
        attributes: [SpanAttribute] = []
    ) {
        self.traceId = traceId
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.name = name
        self.kindRaw = kind.rawValue
        self.startTime = startTime
        self.endTime = endTime
        self.statusRaw = status.rawValue
        self.attributes = attributes
    }
}
```

```swift
// Teloscope/Models/ScopeSpans.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@Model
final class ScopeSpans {
    var scopeName: String
    var scopeVersion: String
    @Relationship(deleteRule: .cascade)
    var spans: [Span]

    init(scopeName: String = "", scopeVersion: String = "", spans: [Span] = []) {
        self.scopeName = scopeName
        self.scopeVersion = scopeVersion
        self.spans = spans
    }
}
```

```swift
// Teloscope/Models/ResourceSpans.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

@Model
final class ResourceAttribute {
    var key: String
    var valueJSON: String

    init(key: String, value: AttributeValue) {
        self.key = key
        self.valueJSON = (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? ""
    }

    var value: AttributeValue? {
        guard let data = valueJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AttributeValue.self, from: data)
    }
}

@Model
final class ResourceSpans {
    var receivedAt: Date
    @Relationship(deleteRule: .cascade)
    var resourceAttributes: [ResourceAttribute]
    @Relationship(deleteRule: .cascade)
    var scopeSpans: [ScopeSpans]

    init(receivedAt: Date = Date(), resourceAttributes: [ResourceAttribute] = [], scopeSpans: [ScopeSpans] = []) {
        self.receivedAt = receivedAt
        self.resourceAttributes = resourceAttributes
        self.scopeSpans = scopeSpans
    }
}
```

```swift
// Teloscope/Models/ResourceMetrics.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Metrics は現フェーズでは rawData 保存のみ。表示は将来フェーズ。
@Model
final class ResourceMetrics {
    var receivedAt: Date
    var rawData: Data

    init(receivedAt: Date = Date(), rawData: Data) {
        self.receivedAt = receivedAt
        self.rawData = rawData
    }
}
```

```swift
// Teloscope/Models/ResourceLogs.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Logs は現フェーズでは rawData 保存のみ。表示は将来フェーズ。
@Model
final class ResourceLogs {
    var receivedAt: Date
    var rawData: Data

    init(receivedAt: Date = Date(), rawData: Data) {
        self.receivedAt = receivedAt
        self.rawData = rawData
    }
}
```

- [ ] **Step 4: `SpanAttribute.value` の `Equatable` 対応（テスト用）**

`SpanTests.attributeValueRoundTrip` で `#expect(attr.value == value)` を使うため、`SpanAttribute.value` が `AttributeValue?` を返し `AttributeValue` が `Equatable` に準拠していることを確認。Step 3 のコードで既に `AttributeValue: Equatable` となっているので追加作業不要。

- [ ] **Step 5: `Item.swift` を削除する**

`Teloscope/Item.swift` を削除。

- [ ] **Step 6: テストが通ることを確認**

Xcode で `SpanTests` を実行。全テストが PASS することを確認。

- [ ] **Step 7: コミット**

```bash
git add Teloscope/Models/ TeloscopeTests/Models/SpanTests.swift
git rm Teloscope/Item.swift
git commit -m "feat: add SwiftData models for OTLP Traces, Metrics, Logs"
```

---

## Task 2: AppSettings

**Files:**
- Create: `Teloscope/Settings/AppSettings.swift`
- Test: `TeloscopeTests/Settings/AppSettingsTests.swift`

- [ ] **Step 1: テストを書く**

```swift
// TeloscopeTests/Settings/AppSettingsTests.swift
// SPDX-License-Identifier: MIT
import Testing
@testable import Teloscope

struct AppSettingsTests {
    @Test func defaultValues() {
        // テスト用に独立したドメインを使う
        let defaults = UserDefaults(suiteName: "test.AppSettingsTests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.port == 4318)
        #expect(settings.autoStart == false)
        #expect(settings.retentionDays == 180)
    }

    @Test func persistsValues() {
        let suiteName = "test.AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.port = 9999
        settings.autoStart = true
        settings.retentionDays = 30
        settings.save()

        let settings2 = AppSettings(defaults: defaults)
        #expect(settings2.port == 9999)
        #expect(settings2.autoStart == true)
        #expect(settings2.retentionDays == 30)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

`AppSettings` 未定義でコンパイルエラーになることを確認。

- [ ] **Step 3: AppSettings を実装する**

```swift
// Teloscope/Settings/AppSettings.swift
// SPDX-License-Identifier: MIT
import Foundation
import Observation

@Observable
final class AppSettings {
    var port: Int
    var autoStart: Bool
    var retentionDays: Int

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        port = defaults.object(forKey: "serverPort") as? Int ?? 4318
        autoStart = defaults.bool(forKey: "autoStart")
        retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 180
    }

    func save() {
        defaults.set(port, forKey: "serverPort")
        defaults.set(autoStart, forKey: "autoStart")
        defaults.set(retentionDays, forKey: "retentionDays")
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

`AppSettingsTests` を実行。PASS を確認。

- [ ] **Step 5: コミット**

```bash
git add Teloscope/Settings/AppSettings.swift TeloscopeTests/Settings/AppSettingsTests.swift
git commit -m "feat: add AppSettings with UserDefaults persistence"
```

---

## Task 3: SPM パッケージ追加と OTLP proto Swift ファイル生成

**Files:**
- Create: `Teloscope/Generated/` (protoc 生成ファイル)

> **Note:** パッケージ追加は Xcode の GUI 操作が必要。

- [ ] **Step 1: swift-nio を Xcode プロジェクトに追加する**

1. `Teloscope.xcodeproj` を Xcode で開く
2. File > Add Package Dependencies
3. URL: `https://github.com/apple/swift-nio`
4. バージョン: Up to Next Major from `2.42.0`（`shutdownGracefully() async throws` が必要）
5. Teloscope ターゲットに `NIO`, `NIOHTTP1` を追加

- [ ] **Step 2: swift-protobuf を Xcode プロジェクトに追加する**

1. File > Add Package Dependencies
2. URL: `https://github.com/apple/swift-protobuf`
3. バージョン: Up to Next Major from `1.0.0`
4. Teloscope ターゲットに `SwiftProtobuf` を追加

- [ ] **Step 3: protoc と protoc-gen-swift をインストールする**

```bash
brew install protobuf
brew install swift-protobuf
```

確認:
```bash
protoc --version
# libprotoc 28.x
protoc-gen-swift --version
# protoc-gen-swift 1.x.x
```

- [ ] **Step 4: OTLP proto ファイルをダウンロードする**

```bash
cd /Users/user/work/cocoa/Teloscope
curl -L https://github.com/open-telemetry/opentelemetry-proto/archive/refs/tags/v1.3.2.tar.gz -o /tmp/otel-proto.tar.gz
tar xzf /tmp/otel-proto.tar.gz -C /tmp/
```

- [ ] **Step 5: Swift ファイルを生成する**

```bash
mkdir -p Teloscope/Generated
PROTO_SRC=/tmp/opentelemetry-proto-1.3.2

protoc \
  --swift_out=Teloscope/Generated \
  --swift_opt=Visibility=Internal \
  -I "$PROTO_SRC" \
  "$PROTO_SRC/opentelemetry/proto/common/v1/common.proto" \
  "$PROTO_SRC/opentelemetry/proto/resource/v1/resource.proto" \
  "$PROTO_SRC/opentelemetry/proto/trace/v1/trace.proto" \
  "$PROTO_SRC/opentelemetry/proto/collector/trace/v1/trace_service.proto" \
  "$PROTO_SRC/opentelemetry/proto/metrics/v1/metrics.proto" \
  "$PROTO_SRC/opentelemetry/proto/collector/metrics/v1/metrics_service.proto" \
  "$PROTO_SRC/opentelemetry/proto/logs/v1/logs.proto" \
  "$PROTO_SRC/opentelemetry/proto/collector/logs/v1/logs_service.proto"
```

以下のファイルが `Teloscope/Generated/` に生成される:
- `opentelemetry_proto_common_v1_common.pb.swift`
- `opentelemetry_proto_resource_v1_resource.pb.swift`
- `opentelemetry_proto_trace_v1_trace.pb.swift`
- `opentelemetry_proto_collector_trace_v1_trace_service.pb.swift`
- `opentelemetry_proto_metrics_v1_metrics.pb.swift`
- `opentelemetry_proto_collector_metrics_v1_metrics_service.pb.swift`
- `opentelemetry_proto_logs_v1_logs.pb.swift`
- `opentelemetry_proto_collector_logs_v1_logs_service.pb.swift`

- [ ] **Step 6: ビルドが通ることを確認する**

Xcode でビルド（Cmd+B）。`import SwiftProtobuf` と生成ファイルが解決されることを確認。

- [ ] **Step 7: クリーンアップしてコミット**

```bash
rm /tmp/otel-proto.tar.gz
git add Teloscope/Generated/
git commit -m "feat: add generated OTLP Protobuf Swift files"
```

---

## Task 4: OTLPRequest + OTLPHTTPHandler + OTLPServer

**Files:**
- Create: `Teloscope/Server/OTLPRequest.swift`
- Create: `Teloscope/Server/OTLPHTTPHandler.swift`
- Create: `Teloscope/Server/OTLPServer.swift`
- Test: `TeloscopeTests/Server/OTLPServerTests.swift`

- [ ] **Step 1: テストを書く**

```swift
// TeloscopeTests/Server/OTLPServerTests.swift
// SPDX-License-Identifier: MIT
import Testing
import Foundation
@testable import Teloscope

struct OTLPServerTests {
    @Test func serverStartsAndStops() async throws {
        let server = OTLPServer()
        #expect(!server.isRunning)
        try await server.start(port: 14318) { _ in }
        #expect(server.isRunning)
        try await server.stop()
        #expect(!server.isRunning)
    }

    @Test func serverReceivesTracesRequest() async throws {
        let server = OTLPServer()
        var receivedRequests: [OTLPRequest] = []
        try await server.start(port: 14319) { request in
            receivedRequests.append(request)
        }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:14319/v1/traces")!)
        req.httpMethod = "POST"
        req.httpBody = Data([0x01, 0x02])
        req.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        _ = try await URLSession.shared.data(for: req)

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(receivedRequests.count == 1)
        if case .traces(let data) = receivedRequests[0] {
            #expect(data == Data([0x01, 0x02]))
        } else {
            Issue.record("Expected .traces request")
        }

        try await server.stop()
    }

    @Test func serverReturns404ForUnknownPath() async throws {
        let server = OTLPServer()
        try await server.start(port: 14320) { _ in }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:14320/v1/unknown")!)
        req.httpMethod = "POST"
        req.httpBody = Data()
        let (_, response) = try await URLSession.shared.data(for: req)
        let httpResponse = response as! HTTPURLResponse
        #expect(httpResponse.statusCode == 404)

        try await server.stop()
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

`OTLPServer` 未定義でコンパイルエラーになることを確認。

- [ ] **Step 3: OTLPRequest を実装する**

```swift
// Teloscope/Server/OTLPRequest.swift
// SPDX-License-Identifier: MIT
import Foundation

enum OTLPRequest {
    case traces(Data)
    case metrics(Data)
    case logs(Data)
}
```

- [ ] **Step 4: OTLPHTTPHandler を実装する**

```swift
// Teloscope/Server/OTLPHTTPHandler.swift
// SPDX-License-Identifier: MIT
import Foundation
import NIO
import NIOHTTP1

final class OTLPHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let onRequest: (OTLPRequest) -> Void
    private var requestHead: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?

    init(onRequest: @escaping (OTLPRequest) -> Void) {
        self.onRequest = onRequest
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head
            bodyBuffer = context.channel.allocator.buffer(capacity: 256)
        case .body(var buf):
            bodyBuffer?.writeBuffer(&buf)
        case .end:
            guard let head = requestHead, let bodyBuffer else { return }
            handle(context: context, head: head, body: bodyBuffer)
        }
    }

    private func handle(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer) {
        let bytes = Data(body.readableBytesView)
        switch head.uri {
        case "/v1/traces":
            onRequest(.traces(bytes))
            respond(context: context, status: .ok)
        case "/v1/metrics":
            onRequest(.metrics(bytes))
            respond(context: context, status: .ok)
        case "/v1/logs":
            onRequest(.logs(bytes))
            respond(context: context, status: .ok)
        default:
            respond(context: context, status: .notFound)
        }
    }

    private func respond(context: ChannelHandlerContext, status: HTTPResponseStatus) {
        let head = HTTPResponseHead(version: .http1_1, status: status)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
```

- [ ] **Step 5: OTLPServer を実装する**

```swift
// Teloscope/Server/OTLPServer.swift
// SPDX-License-Identifier: MIT
import Foundation
import NIO
import NIOHTTP1
import Observation

@Observable
final class OTLPServer: @unchecked Sendable {
    private(set) var isRunning = false
    var lastError: String?

    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?

    func start(port: Int, onRequest: @escaping (OTLPRequest) -> Void) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        self.group = group

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(OTLPHTTPHandler(onRequest: onRequest))
                }
            }

        do {
            let channel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
            self.channel = channel
            await MainActor.run {
                self.isRunning = true
                self.lastError = nil
            }
        } catch {
            try? await group.shutdownGracefully()
            self.group = nil
            throw error
        }
    }

    func stop() async throws {
        try await channel?.close().get()
        try await group?.shutdownGracefully()
        channel = nil
        group = nil
        await MainActor.run {
            isRunning = false
        }
    }
}
```

- [ ] **Step 6: テストが通ることを確認**

`OTLPServerTests` を実行。全テストが PASS することを確認。

- [ ] **Step 7: コミット**

```bash
git add Teloscope/Server/ TeloscopeTests/Server/OTLPServerTests.swift
git commit -m "feat: add OTLPServer with swift-nio HTTP handler"
```

---

## Task 5: OTLPIngestionService

**Files:**
- Create: `Teloscope/Ingestion/OTLPIngestionService.swift`
- Test: `TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift`

- [ ] **Step 1: テストを書く**

```swift
// TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift
// SPDX-License-Identifier: MIT
import Testing
import SwiftData
import SwiftProtobuf
@testable import Teloscope

struct OTLPIngestionServiceTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ResourceSpans.self, ScopeSpans.self, Span.self, SpanAttribute.self,
            ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self,
            configurations: config
        )
    }

    @Test func ingestsSpanFromTracesRequest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = OTLPIngestionService(modelContext: context)

        var spanProto = Opentelemetry_Proto_Trace_V1_Span()
        spanProto.traceID = Data(repeating: 0xAB, count: 16)
        spanProto.spanID = Data(repeating: 0xCD, count: 8)
        spanProto.name = "test-span"
        spanProto.startTimeUnixNano = 1_000_000_000
        spanProto.endTimeUnixNano = 2_000_000_000
        spanProto.kind = .server
        spanProto.status.code = .ok

        var attrProto = Opentelemetry_Proto_Common_V1_KeyValue()
        attrProto.key = "http.method"
        attrProto.value.stringValue = "GET"
        spanProto.attributes = [attrProto]

        var scopeSpansProto = Opentelemetry_Proto_Trace_V1_ScopeSpans()
        scopeSpansProto.scope.name = "claude-code"
        scopeSpansProto.spans = [spanProto]

        var resourceSpansProto = Opentelemetry_Proto_Trace_V1_ResourceSpans()
        resourceSpansProto.scopeSpans = [scopeSpansProto]

        var request = Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest()
        request.resourceSpans = [resourceSpansProto]
        let data = try request.serializedData()

        service.ingest(.traces(data))

        let spans = try context.fetch(FetchDescriptor<Span>())
        #expect(spans.count == 1)
        #expect(spans[0].name == "test-span")
        #expect(spans[0].kind == .server)
        #expect(spans[0].status == .ok)
        #expect(spans[0].traceId == String(repeating: "ab", count: 16))
        #expect(spans[0].attributes.first?.value == .string("GET"))
    }

    @Test func deletesSpansOlderThanRetentionDays() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let service = OTLPIngestionService(modelContext: context)

        let old = Span(
            traceId: "old", spanId: "s1",
            name: "old-span",
            startTime: Date(timeIntervalSinceNow: -200 * 86400),
            endTime: Date(timeIntervalSinceNow: -200 * 86400 + 1)
        )
        let recent = Span(
            traceId: "recent", spanId: "s2",
            name: "recent-span",
            startTime: Date(timeIntervalSinceNow: -10 * 86400),
            endTime: Date(timeIntervalSinceNow: -10 * 86400 + 1)
        )
        context.insert(old)
        context.insert(recent)
        try context.save()

        service.deleteOldData(retentionDays: 180)

        let spans = try context.fetch(FetchDescriptor<Span>())
        #expect(spans.count == 1)
        #expect(spans[0].name == "recent-span")
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

`OTLPIngestionService` 未定義でコンパイルエラーになることを確認。

- [ ] **Step 3: OTLPIngestionService を実装する**

```swift
// Teloscope/Ingestion/OTLPIngestionService.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import SwiftProtobuf

final class OTLPIngestionService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func ingest(_ request: OTLPRequest) {
        switch request {
        case .traces(let data): ingestTraces(data)
        case .metrics(let data): ingestMetrics(data)
        case .logs(let data): ingestLogs(data)
        }
    }

    private func ingestTraces(_ data: Data) {
        guard let proto = try? Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest(serializedData: data) else { return }
        for rsProto in proto.resourceSpans {
            let rs = ResourceSpans()
            rs.resourceAttributes = rsProto.resource.attributes.map {
                ResourceAttribute(key: $0.key, value: AttributeValue(anyValue: $0.value))
            }
            rs.scopeSpans = rsProto.scopeSpans.map { ssProto in
                let ss = ScopeSpans(scopeName: ssProto.scope.name, scopeVersion: ssProto.scope.version)
                ss.spans = ssProto.spans.map { sProto in
                    let span = Span(
                        traceId: sProto.traceID.hexString,
                        spanId: sProto.spanID.hexString,
                        parentSpanId: sProto.parentSpanID.isEmpty ? nil : sProto.parentSpanID.hexString,
                        name: sProto.name,
                        kind: SpanKind(protoKind: sProto.kind),
                        startTime: Date(unixNano: sProto.startTimeUnixNano),
                        endTime: Date(unixNano: sProto.endTimeUnixNano),
                        status: SpanStatus(protoCode: sProto.status.code),
                        attributes: sProto.attributes.map {
                            SpanAttribute(key: $0.key, value: AttributeValue(anyValue: $0.value))
                        }
                    )
                    return span
                }
                return ss
            }
            modelContext.insert(rs)
        }
        try? modelContext.save()
    }

    private func ingestMetrics(_ data: Data) {
        let metrics = ResourceMetrics(rawData: data)
        modelContext.insert(metrics)
        try? modelContext.save()
    }

    private func ingestLogs(_ data: Data) {
        let logs = ResourceLogs(rawData: data)
        modelContext.insert(logs)
        try? modelContext.save()
    }

    func deleteOldData(retentionDays: Int) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
        let predicate = #Predicate<Span> { $0.startTime < cutoff }
        try? modelContext.delete(model: Span.self, where: predicate)
        try? modelContext.save()
    }
}

// MARK: - Helpers

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

private extension Date {
    init(unixNano: UInt64) {
        self.init(timeIntervalSince1970: Double(unixNano) / 1_000_000_000)
    }
}

private extension AttributeValue {
    init(anyValue: Opentelemetry_Proto_Common_V1_AnyValue) {
        switch anyValue.value {
        case .stringValue(let s): self = .string(s)
        case .intValue(let i): self = .int64(i)
        case .doubleValue(let d): self = .double(d)
        case .boolValue(let b): self = .bool(b)
        case .arrayValue(let arr):
            let strings = arr.values.compactMap { v -> String? in
                if case .stringValue(let s) = v.value { return s }
                return nil
            }
            self = .stringArray(strings)
        default: self = .string("")
        }
    }
}

private extension SpanKind {
    init(protoKind: Opentelemetry_Proto_Trace_V1_Span.SpanKind) {
        switch protoKind {
        case .internal: self = .internal
        case .server: self = .server
        case .client: self = .client
        case .producer: self = .producer
        case .consumer: self = .consumer
        default: self = .unspecified
        }
    }
}

private extension SpanStatus {
    init(protoCode: Opentelemetry_Proto_Trace_V1_Status.StatusCode) {
        switch protoCode {
        case .ok: self = .ok
        case .error: self = .error
        default: self = .unset
        }
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

`OTLPIngestionServiceTests` を実行。全テストが PASS することを確認。

- [ ] **Step 5: コミット**

```bash
git add Teloscope/Ingestion/ TeloscopeTests/Ingestion/OTLPIngestionServiceTests.swift
git commit -m "feat: add OTLPIngestionService with Protobuf decoding and retention"
```

---

## Task 6: TeloscopeApp 統合

**Files:**
- Modify: `Teloscope/TeloscopeApp.swift`
- Modify: `Teloscope/ContentView.swift`（空実装に変更）

- [ ] **Step 1: TeloscopeApp を更新する**

```swift
// Teloscope/TeloscopeApp.swift
// SPDX-License-Identifier: MIT
import SwiftUI
import SwiftData

@main
struct TeloscopeApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ResourceSpans.self,
            ScopeSpans.self,
            Span.self,
            SpanAttribute.self,
            ResourceAttribute.self,
            ResourceMetrics.self,
            ResourceLogs.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var settings = AppSettings()
    @State private var server = OTLPServer()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(settings)
                .environment(server)
                .task {
                    startRetentionTimer()
                    if settings.autoStart {
                        await startServer()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func startServer() async {
        guard !server.isRunning else { return }
        let context = ModelContext(sharedModelContainer)
        let ingestion = OTLPIngestionService(modelContext: context)
        do {
            try await server.start(port: settings.port) { request in
                Task { @MainActor in
                    ingestion.ingest(request)
                }
            }
        } catch {
            await MainActor.run {
                server.lastError = error.localizedDescription
            }
        }
    }

    private func startRetentionTimer() {
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            let context = ModelContext(sharedModelContainer)
            let service = OTLPIngestionService(modelContext: context)
            service.deleteOldData(retentionDays: settings.retentionDays)
        }
        // 起動時にも実行
        let context = ModelContext(sharedModelContainer)
        let service = OTLPIngestionService(modelContext: context)
        service.deleteOldData(retentionDays: settings.retentionDays)
    }
}
```

- [ ] **Step 2: ContentView をプレースホルダーに変更する（MainView 実装まで）**

```swift
// Teloscope/ContentView.swift
// SPDX-License-Identifier: MIT
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Loading...")
    }
}
```

> MainView は Task 8 で実装する。TeloscopeApp は ContentView の代わりに MainView を直接使うためこのファイルは削除してもよい。

- [ ] **Step 3: ビルドが通ることを確認**

Xcode でビルド（Cmd+B）。エラーなしを確認。

- [ ] **Step 4: コミット**

```bash
git add Teloscope/TeloscopeApp.swift Teloscope/ContentView.swift
git commit -m "feat: integrate OTLPServer and OTLPIngestionService into app lifecycle"
```

---

## Task 7: Settings UI

**Files:**
- Create: `Teloscope/Views/Settings/SettingsView.swift`

- [ ] **Step 1: SettingsView を実装する**

```swift
// Teloscope/Views/Settings/SettingsView.swift
// SPDX-License-Identifier: MIT
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(OTLPServer.self) private var server
    @State private var portText = ""

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Server") {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("4318", text: $portText)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onSubmit { applyPort() }
                        .onChange(of: portText) { applyPort() }
                }
                Toggle("Start server on app launch", isOn: $settings.autoStart)
                    .onChange(of: settings.autoStart) { settings.save() }
            }
            Section("Data") {
                HStack {
                    Text("Retention (days)")
                    Spacer()
                    TextField("180", value: $settings.retentionDays, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: settings.retentionDays) { settings.save() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            portText = "\(settings.port)"
        }
    }

    private func applyPort() {
        if let port = Int(portText), port > 0, port <= 65535 {
            settings.port = port
            settings.save()
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
        .environment(OTLPServer())
}
```

- [ ] **Step 2: ビルドが通ることを確認**

Cmd+B でエラーなし。Preview が表示されることを Xcode で確認。

- [ ] **Step 3: コミット**

```bash
git add Teloscope/Views/Settings/SettingsView.swift
git commit -m "feat: add SettingsView for port, auto-start, retention"
```

---

## Task 8: MainView（ナビゲーション構造）

**Files:**
- Create: `Teloscope/Views/MainView.swift`

- [ ] **Step 1: MainView を実装する**

```swift
// Teloscope/Views/MainView.swift
// SPDX-License-Identifier: MIT
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case traces = "Traces"
    case metrics = "Metrics"
    case logs = "Logs"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .traces: return "chart.bar.doc.horizontal"
        case .metrics: return "chart.line.uptrend.xyaxis"
        case .logs: return "doc.text"
        case .settings: return "gear"
        }
    }
}

struct MainView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(OTLPServer.self) private var server
    @State private var selectedItem: SidebarItem? = .traces

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label(item.rawValue, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selectedItem {
            case .traces: TraceListView()
            case .metrics: ContentUnavailableView("Metrics", systemImage: "chart.line.uptrend.xyaxis", description: Text("Coming soon"))
            case .logs: ContentUnavailableView("Logs", systemImage: "doc.text", description: Text("Coming soon"))
            case .settings: SettingsView()
            case nil: ContentUnavailableView("Select an item", systemImage: "sidebar.left")
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                serverToggleButton
            }
        }
    }

    @ViewBuilder
    private var serverToggleButton: some View {
        if server.isRunning {
            Button {
                Task { try? await server.stop() }
            } label: {
                Label("Stop Server", systemImage: "stop.circle.fill")
                    .foregroundStyle(.green)
            }
            .help("OTLP server running on port \(settings.port). Click to stop.")
        } else {
            Button {
                Task {
                    // OTLPIngestionService はここでは直接生成できないため
                    // TeloscopeApp の startServer() を呼ぶ代わりに Notification を使う
                    NotificationCenter.default.post(name: .startOTLPServer, object: nil)
                }
            } label: {
                Label("Start Server", systemImage: "play.circle")
            }
            .help("Click to start OTLP server on port \(settings.port)")
        }
    }
}

extension Notification.Name {
    static let startOTLPServer = Notification.Name("startOTLPServer")
}

#Preview {
    MainView()
        .environment(AppSettings())
        .environment(OTLPServer())
        .modelContainer(for: [ResourceSpans.self, ScopeSpans.self, Span.self, SpanAttribute.self, ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self], inMemory: true)
}
```

- [ ] **Step 2: TeloscopeApp で Notification を受け取る**

`TeloscopeApp.swift` の `body` に以下を追加:

```swift
.task {
    startRetentionTimer()
    if settings.autoStart {
        await startServer()
    }
    // ツールバーの Start Server ボタンからの通知を受け取る
    for await _ in NotificationCenter.default.notifications(named: .startOTLPServer) {
        await startServer()
    }
}
```

（既存の `.task` ブロックを上記で置き換える）

- [ ] **Step 3: ビルドが通ることを確認**

Cmd+B でエラーなし。

- [ ] **Step 4: コミット**

```bash
git add Teloscope/Views/MainView.swift Teloscope/TeloscopeApp.swift
git commit -m "feat: add MainView with NavigationSplitView and server toggle toolbar"
```

---

## Task 9: TraceListView

**Files:**
- Create: `Teloscope/Views/Traces/TraceListView.swift`

- [ ] **Step 1: TraceListView を実装する**

```swift
// Teloscope/Views/Traces/TraceListView.swift
// SPDX-License-Identifier: MIT
import SwiftUI
import SwiftData

struct TraceRow: Identifiable {
    let id: String  // traceId
    let traceId: String
    let startTime: Date
    let spanCount: Int
    let rootSpanName: String
}

struct TraceListView: View {
    @Query(sort: \Span.startTime, order: .reverse) private var allSpans: [Span]
    @State private var selectedTraceId: String?

    private var traces: [TraceRow] {
        let grouped = Dictionary(grouping: allSpans, by: \.traceId)
        return grouped.map { traceId, spans in
            let rootSpan = spans.first { $0.parentSpanId == nil } ?? spans[0]
            return TraceRow(
                id: traceId,
                traceId: traceId,
                startTime: rootSpan.startTime,
                spanCount: spans.count,
                rootSpanName: rootSpan.name
            )
        }
        .sorted { $0.startTime > $1.startTime }
    }

    private var selectedSpans: [Span] {
        guard let traceId = selectedTraceId else { return [] }
        return allSpans.filter { $0.traceId == traceId }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VSplitView {
            traceTable
                .frame(minHeight: 150)
            if selectedTraceId != nil {
                GanttChartView(spans: selectedSpans)
                    .frame(minHeight: 200)
            } else {
                ContentUnavailableView(
                    "Select a Trace",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Select a trace from the list above to see the Gantt chart")
                )
            }
        }
        .navigationTitle("Traces")
    }

    private var traceTable: some View {
        Table(traces, selection: $selectedTraceId) {
            TableColumn("Trace ID") { row in
                Text(String(row.traceId.prefix(16)))
                    .font(.system(.body, design: .monospaced))
            }
            TableColumn("Root Span") { row in
                Text(row.rootSpanName)
            }
            TableColumn("Start Time") { row in
                Text(row.startTime.formatted(.dateTime.hour().minute().second().secondFraction(.milliseconds(3))))
            }
            TableColumn("Spans") { row in
                Text("\(row.spanCount)")
            }
        }
    }
}

#Preview {
    TraceListView()
        .modelContainer(for: [ResourceSpans.self, ScopeSpans.self, Span.self, SpanAttribute.self, ResourceAttribute.self, ResourceMetrics.self, ResourceLogs.self], inMemory: true)
}
```

- [ ] **Step 2: ビルドが通ることを確認**

Cmd+B でエラーなし。

- [ ] **Step 3: コミット**

```bash
git add Teloscope/Views/Traces/TraceListView.swift
git commit -m "feat: add TraceListView with Table and split layout"
```

---

## Task 10: GanttChartView + SpanDetailView

**Files:**
- Create: `Teloscope/Views/Traces/GanttChartView.swift`
- Create: `Teloscope/Views/Traces/SpanDetailView.swift`

- [ ] **Step 1: SpanDetailView を実装する**

```swift
// Teloscope/Views/Traces/SpanDetailView.swift
// SPDX-License-Identifier: MIT
import SwiftUI

struct SpanDetailView: View {
    let span: Span

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(span.name)
                .font(.headline)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                detailRow("Trace ID", span.traceId)
                detailRow("Span ID", span.spanId)
                if let parent = span.parentSpanId {
                    detailRow("Parent Span ID", parent)
                }
                detailRow("Kind", "\(span.kind)")
                detailRow("Status", "\(span.status)")
                detailRow("Duration", durationText)
            }
            if !span.attributes.isEmpty {
                Divider()
                Text("Attributes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                    ForEach(span.attributes, id: \.key) { attr in
                        detailRow(attr.key, attr.value.map { "\($0)" } ?? "")
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: 400)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var durationText: String {
        let ms = span.endTime.timeIntervalSince(span.startTime) * 1000
        return String(format: "%.2f ms", ms)
    }
}
```

- [ ] **Step 2: GanttChartView を実装する**

```swift
// Teloscope/Views/Traces/GanttChartView.swift
// SPDX-License-Identifier: MIT
import SwiftUI
import Charts

struct GanttChartView: View {
    let spans: [Span]
    @State private var selectedSpan: Span?

    private var traceStart: Date {
        spans.map(\.startTime).min() ?? Date()
    }

    private func msOffset(_ date: Date) -> Double {
        date.timeIntervalSince(traceStart) * 1000
    }

    private func indentLevel(for span: Span) -> Int {
        var level = 0
        var currentId = span.parentSpanId
        while let parentId = currentId {
            level += 1
            currentId = spans.first { $0.spanId == parentId }?.parentSpanId
            if level > 20 { break }  // 循環参照ガード
        }
        return level
    }

    var body: some View {
        ScrollView(.vertical) {
            Chart(spans, id: \.spanId) { span in
                BarMark(
                    xStart: .value("Start", msOffset(span.startTime)),
                    xEnd: .value("End", max(msOffset(span.endTime), msOffset(span.startTime) + 1)),
                    y: .value("Span", spanLabel(span))
                )
                .foregroundStyle(barColor(for: span))
                .cornerRadius(2)
            }
            .chartXAxisLabel("Time (ms)", alignment: .center)
            .chartYAxis {
                AxisMarks(preset: .aligned) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            let y = location.y - geo[proxy.plotFrame!].minY
                            if let label = proxy.value(atY: y, as: String.self) {
                                selectedSpan = spans.first { spanLabel($0) == label }
                            }
                        }
                }
            }
            .frame(height: CGFloat(spans.count) * 28 + 60)
            .padding()
        }
        .popover(item: $selectedSpan) { span in
            SpanDetailView(span: span)
        }
    }

    private func spanLabel(_ span: Span) -> String {
        let indent = String(repeating: "  ", count: indentLevel(for: span))
        return "\(indent)\(span.name)"
    }

    private func barColor(for span: Span) -> Color {
        switch span.status {
        case .error: return .red.opacity(0.8)
        case .ok: return .blue.opacity(0.7)
        case .unset: return .gray.opacity(0.6)
        }
    }
}

#Preview {
    let now = Date()
    let spans = [
        Span(traceId: "t1", spanId: "s1", name: "root", kind: .server,
             startTime: now, endTime: now.addingTimeInterval(0.5), status: .ok),
        Span(traceId: "t1", spanId: "s2", parentSpanId: "s1", name: "child-1", kind: .internal,
             startTime: now.addingTimeInterval(0.05), endTime: now.addingTimeInterval(0.2)),
        Span(traceId: "t1", spanId: "s3", parentSpanId: "s1", name: "child-2", kind: .client,
             startTime: now.addingTimeInterval(0.25), endTime: now.addingTimeInterval(0.45), status: .error),
    ]
    GanttChartView(spans: spans)
        .frame(width: 600, height: 300)
}
```

- [ ] **Step 3: ビルドが通ることを確認**

Cmd+B でエラーなし。Preview でガントチャートが表示されることを確認。

- [ ] **Step 4: コミット**

```bash
git add Teloscope/Views/Traces/
git commit -m "feat: add GanttChartView and SpanDetailView for Traces UI"
```

---

## Task 11: 動作確認

- [ ] **Step 1: アプリを起動して Settings を開き、ポート番号を確認する**

Settings サイドバーアイテムを選択。ポートが 4318、自動起動が OFF であることを確認。

- [ ] **Step 2: ツールバーの Start Server ボタンでサーバーを起動する**

ボタンをクリック → ツールバーアイコンが緑になることを確認。

- [ ] **Step 3: Claude Code の OTLP エンドポイントを設定する**

Claude Code の設定で OTLP エンドポイントを `http://127.0.0.1:4318` に設定し、Claude Code を使って操作する。

- [ ] **Step 4: Traces 画面でデータを確認する**

Traces サイドバーアイテムを選択。テーブルに Trace 行が表示され、選択するとガントチャートが表示されることを確認。

- [ ] **Step 5: コミット（必要なら最終調整後）**

```bash
git add -p
git commit -m "fix: final adjustments after end-to-end testing"
```
