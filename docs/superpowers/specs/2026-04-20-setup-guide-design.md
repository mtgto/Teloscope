# Setup Guide / Onboarding Sheet — Design Spec

**Date:** 2026-04-20

## Problem

新規ユーザーがTeloscopeを起動した際、Claude Codeへの設定方法がわからない。また既存ユーザーが設定方法を再確認したい場合に参照する場所がない。

## Goal

- 初回起動時に自動でセットアップガイドをシートで表示する
- 設定画面の「?」ボタンから再度表示できる
- JSONスニペットはポート番号を動的に反映し、クリップボードへコピーできる
- サーバーが未起動の場合、シートから直接起動できる

---

## Architecture

### 新規ファイル

**`Teloscope/Views/Settings/SetupGuideView.swift`**

- `AppSettings` と `OTLPServer` を `@Environment` で受け取る
- `settings.port` を使ってJSONスニペットを動的生成
- `OTLPServer.isRunning` の状態を監視してサーバー状態表示を切り替え
- Start Server ボタンは `NotificationCenter.default.post(name: .startOTLPServer, object: nil)` で起動

### 変更ファイル

**`Teloscope/Views/MainView.swift`**
- `@AppStorage("hasSeenSetupGuide") private var hasSeenSetupGuide = false` を追加
- `.onAppear` でフラグを確認し未表示なら `.sheet(isPresented:)` で `SetupGuideView` を表示
- シートを閉じたら `hasSeenSetupGuide = true` にセット

**`Teloscope/Views/Settings/SettingsView.swift`**
- `@State private var showingSetupGuide = false` を追加
- `Form` を `ZStack` でラップし、右下に「?」ボタンを `.overlay` で配置
- タップで `showingSetupGuide = true` → `.sheet` で `SetupGuideView` を表示

---

## SetupGuideView UI

```
┌─────────────────────────────────────────┐
│  Getting Started                        │
│                                         │
│  Teloscope is running on port 4318.     │  ← isRunning == true
│  ─── or ───                             │
│  ⚠ Server is not running.              │  ← isRunning == false
│  [Start Server]                         │
│                                         │
│  Add the following to your Claude Code  │
│  settings to send telemetry here:       │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ // ~/.claude/settings.json      │    │
│  │ {                               │    │
│  │   "env": {                      │    │
│  │     "CLAUDE_CODE_ENABLE_        │    │
│  │       TELEMETRY": "1",          │    │
│  │     "OTEL_EXPORTER_OTLP_        │    │
│  │       ENDPOINT":                │    │
│  │       "http://localhost:XXXX",  │    │
│  │     ...                         │    │
│  │   }                             │    │
│  │ }                               │    │
│  └─────────────────────────────────┘    │
│                          [Copy] [Close] │
└─────────────────────────────────────────┘
```

- コードブロック: `ScrollView` + `.font(.system(.body, design: .monospaced))`
- **Copy** ボタン: `NSPasteboard` にJSONスニペット全体をコピー
- **Start Server**: `isRunning == false` のときだけ表示。`NotificationCenter` 経由で起動
- ポート: `settings.port` を文字列補間で挿入

---

## JSONスニペット（動的ポート版）

```json
// ~/.claude/settings.json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:<port>",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_TRACES_EXPORTER": "otlp"
  }
}
```

`<port>` は `settings.port` の値で置換される。

---

## Localizable.xcstrings への追加が必要な文字列

- `"Getting Started"`
- `"Teloscope is running on port %lld."` (with port argument)
- `"Server is not running."`
- `"Start Server"`
- `"Add the following to your Claude Code settings to send telemetry here:"`
- `"Copy"`
- `"Close"`

---

## Verification

1. アプリをリセット（UserDefaultsを削除）して起動 → シートが自動表示されること
2. シートを閉じて再起動 → シートが表示されないこと
3. 設定画面で「?」ボタンをクリック → シートが表示されること
4. サーバーが未起動の状態でシートを開き「Start Server」をクリック → サーバーが起動し、ポート表示に切り替わること
5. 設定でポートを変更してから「?」を開く → スニペット内のポートが反映されていること
6. Copyボタンをクリック → クリップボードに正しいJSONが入ること
