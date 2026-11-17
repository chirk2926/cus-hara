# カスハラ防衛線

理不尽なお客さんがキレる前に、言葉だけで切り抜ける接客サバイバルゲーム（Windows向け、Godot 4.5、簡易3D）。

- 舞台: 日本のコンビニ／ゲームセンター（クレーンゲームだらけ）
- お客さん: Claude API のキーを入れるとAIが毎回生成。キーが無くても内蔵の台本で遊べる
- 操作: 返事を自由入力（定型文ボタンで追加もできる）。考えている間、怒りゲージが上がる
- 対戦: 2人で客役と店員役に分かれて対決（2ラウンドで交代、レーティングあり）

> **開発中です。** 自動テスト（1人用・対戦の自動プレイ、Windows出力）は通っていますが、Windows実機での起動、AIモードの実通信、Steam接続はまだ確認できていません。現状と残作業は [docs/HANDOVER.md](docs/HANDOVER.md) を最初に読んでください。

## 動かし方

1. [Godot 4.5](https://godotengine.org)（標準版）を入れる
2. Godot で `project.godot` をインポートして F5

Windows 用 exe は、GitHub に push すると Actions が作ります（成果物 `CusHara-windows`）。

## 資料

| 資料 | 内容 |
|---|---|
| [docs/HANDOVER.md](docs/HANDOVER.md) | 引き継ぎ書。現状・未確認事項・残作業 |
| [docs/REQUIREMENTS_LOG.md](docs/REQUIREMENTS_LOG.md) | 依頼者からの指示の記録 |
| [docs/SPEC.md](docs/SPEC.md) | 仕様書（ルール、数値、データの形、AI連携、対戦モード） |
| [docs/DESIGN.md](docs/DESIGN.md) | 設計書（ファイル構成、責務、処理の流れ） |
| [docs/MAINTENANCE.md](docs/MAINTENANCE.md) | 保守・ビルド・Steam / Microsoft Store 配布の手順 |

## ライセンス表記

フォント Noto Sans JP は SIL Open Font License 1.1（`assets/fonts/OFL.txt`）。
