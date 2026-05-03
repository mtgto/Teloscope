# Visual Regression Testing (VRT) Design

**Date:** 2026-04-21  
**Status:** Approved

## Context

Teloscope は SwiftUI を使って多数のウィジェット View（折れ線グラフ、円グラフ、ヒートマップ、ガントチャートなど）を提供している。UI の意図しない変更を早期に検知するため、SwiftUI Preview を使った VRT を GitHub Actions 上に構築する。有料の外部サービスなしに、PR の Checks 画面から直接差分を確認できる仕組みを目指す。

## Goals

- SwiftUI Preview を PNG としてスナップショット化し、baselineとの差分を自動検出する
- 差分画像（baseline | diff強調 | new の3枚並列PNG）を GitHub Actions Job Summary に埋め込み、ダウンロード不要で確認できる
- main への push 時に baseline を自動更新する
- PR 時に意図した変更であればメンテナーが `vrt-approved` ラベルで baseline 更新を承認できる

## Non-Goals

- PR コメントへの画像投稿（Job Summary で十分）
- スライダー式のインタラクティブ比較（Job Summary では JavaScript が使えないため）
- opt-in 方式による対象 Preview の絞り込み（プロジェクトが大きくなったら検討）

## Architecture

### ブランチ構成

- `main` — アプリ本体のソースコード
- `vrt-baselines` (orphan) — baseline PNG 群を保管する専用ブランチ
  - `TeloscopeTests/__Snapshots__/**/*.png` と同じパス構成で格納

### コンポーネント

| コンポーネント | 役割 |
|---|---|
| `TeloscopeTests/VRT/PreviewSnapshotTests.swift` | 全 Preview を `assertSnapshot` でテスト |
| `scripts/vrt-report.py` | xcresult から差分抽出・3枚並列 PNG 生成・Job Summary 書き出し |
| `.github/workflows/vrt.yml` | PR 比較と main push 時の baseline 更新 |
| `.github/workflows/update-baseline.yml` | `vrt-approved` ラベル付与時の baseline 更新 |

### 依存ライブラリ

- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) — SwiftUI View を PNG に書き出す
- Python `Pillow` — 3枚並列 PNG の合成（macOS runner 上で `pip install Pillow`）

## Workflows

### ワークフロー①：PR 時の VRT チェック（`vrt.yml`）

```
1. checkout
2. vrt-baselines ブランチから PNG を Snapshots/Baseline/ に取得
3. RECORD_SNAPSHOTS=true で xcodebuild test
   （swift-snapshot-testing が __Snapshots__/ に新しい PNG を生成）
4. vrt-report.py が Snapshots/Baseline/ と __Snapshots__/ を比較
5. 差分あり（1%超）？
   YES → 3枚並列 PNG 生成 → Job Summary に base64 埋め込み → exit 1（CI 失敗）
   NO  → Job Summary に "All passed" 表示 → exit 0（CI 成功）
```

> Note: Swift Testing（`@Test` マクロ）は XCTAttachment に対応しないため、xcresult からの差分抽出は使用しない。記録モードで新規 PNG を生成してから baseline と直接比較する方式を採用する。

### ワークフロー②：main push 時の baseline 自動更新（`vrt.yml`）

```
1. checkout
2. RECORD_SNAPSHOTS=true で xcodebuild test
   （swift-snapshot-testing が __Snapshots__ を再生成）
3. vrt-baselines ブランチに commit & push
```

### ワークフロー③：vrt-approved ラベルによる baseline 更新（`update-baseline.yml`）

```
1. pull_request: types: [labeled] でトリガー
2. ラベル名が `vrt-approved` か確認
3. GitHub API でラベル付与者の write 権限を確認（なければ失敗終了）
4. PR ブランチを checkout
5. RECORD_SNAPSHOTS=true で xcodebuild test
6. vrt-baselines ブランチに commit & push
7. VRT チェックが自動再実行されてパス
```

## スナップショットテストの構造

```swift
// TeloscopeTests/VRT/PreviewSnapshotTests.swift
import SnapshotTesting
import SwiftUI

@Suite struct PreviewSnapshotTests {
    // 各 Preview バリエーションを個別にテスト
    @Test func pieWidgetView_default() { ... }
    @Test func pieWidgetView_noData() { ... }
    @Test func lineWidgetView_multiSeries() { ... }
    // ... 全 Preview をカバー
}
```

- 環境変数 `RECORD_SNAPSHOTS=true` のとき記録モード（既存スナップショットを上書き）
- 未設定時は比較モード（差分があればテスト失敗）

## 差分判定の閾値

- 変化ピクセルが全体の **1%超** でその View を「失敗」と判定
- 閾値は `vrt-report.py` の定数として定義し、後から調整可能にする

## Job Summary の表示形式

```markdown
## VRT Results — 2 differences found

### LineWidgetView_multiSeries (1.2% changed) ❌
![diff](data:image/png;base64,...)

### PieWidgetView_default (3.5% changed) ❌
![diff](data:image/png;base64,...)

---
To approve: add label `vrt-approved` to this PR
```

差分がない場合：
```markdown
## VRT Results — All passed ✅
```

## セキュリティ

`vrt-approved` ラベルはリポジトリの triage 権限以上があれば誰でも付与できる。これを悪用した不正な baseline 更新を防ぐため、`update-baseline.yml` の冒頭で GitHub API を使いラベル付与者の write 権限を確認する。権限がなければ `core.setFailed()` でワークフローを終了する。

## Verification

1. `vrt-baselines` orphan ブランチを作成し、初期 baseline を生成して push できること
2. PR で View に意図的な変更を加えたとき、VRT CI が失敗し Job Summary に差分画像が表示されること
3. `vrt-approved` ラベルを付与したとき、権限チェックが通り baseline が更新されること
4. 権限のないユーザーが `vrt-approved` ラベルを付けても `update-baseline.yml` が失敗すること
5. main に変更を push したとき、baseline が自動更新されること
