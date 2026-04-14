# Teloscope: OTLP Collection & Traces UI Design

**Date:** 2026-04-14  
**Scope:** OTLPサーバー（Traces/Metrics/Logs受信）+ Trace一覧・ガントチャートUI  
**Target:** macOS 14+、Claude Code専用

---

## Overview

Teloscope は Claude Code が送出する OTLP/HTTP データを受け取り、SwiftData に保存し、Traces を中心に可視化する macOS アプリ。高額なマネージドサービス（Datadog, Google Cloud等）を契約せずに Claude Code のテレメトリを手軽に確認するのが目的。

---

## Architecture

```
Claude Code
    │  OTLP/HTTP (POST /v1/traces, /v1/metrics, /v1/logs)
    ▼
OTLPServer (swift-nio + swift-protobuf)
    │  デコード済みの Swift 型
    ▼
OTLPIngestionService
    │  SwiftData (ModelContainer)
    ▼
SwiftUI Views
```

### コンポーネント責務

| コンポーネント | 責務 |
|---|---|
| `OTLPServer` | swift-nio による HTTP リスナー。ポート管理・起動/停止・リクエスト受信のみ担当。受信データをコールバックで IngestionService に渡す |
| `OTLPIngestionService` | Protobuf デコード済みデータを SwiftData モデルに変換・保存。保持期間を超えた古いデータの削除（起動時 + 1時間ごと） |
| SwiftUI Views | `@Query` で SwiftData を直接参照。サーバー状態は `OTLPServer` を `@Observable` または `EnvironmentObject` として参照 |

### 依存パッケージ（SPM）

- `apple/swift-nio` — HTTP サーバー
- `apple/swift-protobuf` — Protobuf デコード
- OpenTelemetry の公式 `.proto` ファイルから生成した Swift コード（`opentelemetry-proto`）

---

## Data Model

OTLPの仕様の階層構造に合わせてSwiftDataモデルを定義する。

### Traces

```swift
// ResourceSpans: サービス（resource）単位のSpanコンテナ
@Model class ResourceSpans {
    var resource: [String: AttributeValue]  // service.name など
    var scopeSpans: [ScopeSpans]
    var receivedAt: Date
}

// ScopeSpans: 計装ライブラリ単位
@Model class ScopeSpans {
    var scopeName: String
    var scopeVersion: String
    var spans: [Span]
}

// SpanAttribute: Span の属性 (SwiftData は辞書型を直接サポートしないため別モデル)
@Model class SpanAttribute {
    var key: String
    var value: AttributeValue  // Codable な enum を @Attribute(.transformable) で保存
}

// Span: 個々のスパン
@Model class Span {
    var traceId: String        // hex string
    var spanId: String         // hex string
    var parentSpanId: String?  // nil = root span
    var name: String
    var kind: SpanKind
    var startTime: Date
    var endTime: Date
    var attributes: [SpanAttribute]
    var status: SpanStatus
}

enum SpanKind: Int, Codable { case unspecified, internal_, server, client, producer, consumer }
enum SpanStatus: Int, Codable { case unset, ok, error }
```

- **Trace** という独立モデルは持たない。同じ `traceId` を持つ `Span` の集合がTrace。
- `AttributeValue` は `string / int64 / double / bool / stringArray` を保持できる enum（Codable）。

### Metrics・Logs

同様に `ResourceMetrics`, `ResourceLogs` を定義して保存のみ対応。表示は今フェーズのスコープ外。

### データ保持

- 保持期間はデフォルト180日（約半年）、Settings で変更可能。
- `Span.startTime` が保持期間より古いレコードをまとめて削除。
- 削除タイミング: アプリ起動時 + 1時間ごと。

---

## UI Structure

macOS 標準の `NavigationSplitView` を使った2カラム構成（サイドバー＋メインコンテンツ）。

```
┌──────────────┬──────────────────────────────────────┐
│ サイドバー     │  メインコンテンツ                       │
│              │                                      │
│ ● Traces    │  【Traces選択時】                      │
│   Metrics   │  上: Trace一覧テーブル                  │
│   Logs      │     (traceId先頭8文字, 開始時刻, span数) │
│   Settings  │  下: 選択Traceのガントチャート             │
│              │      横軸=経過時間(ms)                  │
│              │      行=Span名(階層インデント)           │
│              │      Spanクリック→attributesポップオーバー│
└──────────────┴──────────────────────────────────────┘
```

- ガントチャートは `SwiftCharts` の `BarMark` で実装（横軸: 開始Spanからの経過ms、各行: Span）
- Span の階層（parentSpanId）はインデントで表現
- サーバーの ON/OFF トグルはウィンドウツールバーに常時表示（起動中は緑インジケーター）

---

## Settings

| 設定項目 | UI | デフォルト |
|---|---|---|
| サーバーポート | テキストフィールド（数値バリデーション付き） | 4318 |
| アプリ起動時に自動でサーバー起動 | チェックボックス | OFF |
| データ保持期間（日数） | テキストフィールド | 180 |

設定値は `UserDefaults` に保存（SwiftData不要）。

---

## Error Handling

| 状況 | 対処 |
|---|---|
| 不正なOTLPリクエスト（パース失敗・未知エンドポイント） | HTTP 400 を返す。アプリはクラッシュしない |
| ポートが使用中でサーバー起動失敗 | UI上にエラーバナーを表示。再試行ボタンを提供 |
| SwiftData 保存失敗 | 警告ログのみ。データ欠損を許容 |

---

## Testing

| 対象 | 手法 |
|---|---|
| `OTLPIngestionService` | ユニットテスト。サンプルProtobufバイナリを渡してSwiftDataモデルへの変換を検証 |
| `OTLPServer` | 結合テスト。ローカルにHTTPリクエストを送りエンドツーエンドで動作確認 |
| SwiftUI Views | 自動テスト対象外。Preview用モックデータを用意 |

---

## Out of Scope（今フェーズ）

- Metrics・Logs の表示UI
- カレンダー表示・ツール使用ランキング
- Claude Code 以外のOTLPクライアント対応
- OTLP/gRPC 対応（OTLP/HTTP のみ）
