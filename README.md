# カスハラ防衛線 / Kasuhara Defense Line – Calm the Angry Customer

理不尽なお客さんがキレる前に、言葉だけで切り抜ける接客サバイバルゲーム（Windows、Godot 4.5、簡易3D）。日本語・英語・中国語（簡体字）・韓国語の4言語。

- **舞台**: 日本のコンビニ／ゲームセンター（クレーンゲームだらけ）
- **1人用**: 1シフト4人のお客さんを相手に、返事を書いて納得させる。考えている間、怒りが上がる
- **対戦**: 2人で客役と店員役に分かれて対決（2ラウンドで交代）。ランクマッチ（レーティング）とフレンド対戦（部屋コード）、文字と音声（押して話す）
- **AI**: ゲームサーバーが Claude を呼んでお客さんを作り、返事を採点する。APIキーはサーバーだけが持つ。サーバーが無くても台本で遊べる

> **開発中です。** 自動テスト（サーバーのテスト、1人用と対戦の自動プレイ、Windows出力）は通っていますが、Windows実機での操作、本物のAI・文字起こしとの接続、サーバーの公開はまだです。現状と残作業は [docs/HANDOVER.md](docs/HANDOVER.md) を最初に読んでください。

## 動かし方

1. ゲームサーバー（Node.js 22.18 以上）:

```bash
cd server && npm ci && npm start
```

`ANTHROPIC_API_KEY` を設定するとAIが動きます（無くてもキーワード判定で遊べます）。本番では管理画面の「AIのAPI」で、Claude・OpenAI・Gemini・DeepSeek を最大5個、優先順位つきで登録できます（docs/SERVER.md 9.2）。

2. ゲーム: [Godot 4.5](https://godotengine.org)（標準版）で `project.godot` をインポートして F5。

Windows 用 exe と Microsoft Store 用 MSIX は、GitHub に push すると Actions が作ります（成果物 `CusHara-windows` / `CusHara-msix`）。

## 資料

| 資料 | 内容 |
|---|---|
| [docs/HANDOVER.md](docs/HANDOVER.md) | 引き継ぎ書。現状・未確認事項・残作業 |
| [docs/REQUIREMENTS_LOG.md](docs/REQUIREMENTS_LOG.md) | 依頼者からの指示の記録 |
| [docs/SPEC.md](docs/SPEC.md) | 仕様書（ルール、数値、データの形、AI、対戦、多言語） |
| [docs/DESIGN.md](docs/DESIGN.md) | 設計書（全体像、ファイル構成、処理の流れ） |
| [docs/SERVER.md](docs/SERVER.md) | ゲームサーバー（起動、環境変数、API、WebSocket のメッセージ） |
| [docs/UI_GUIDE.md](docs/UI_GUIDE.md) | 画面の作り方（AIっぽく見せないための決まり） |
| [docs/MAINTENANCE.md](docs/MAINTENANCE.md) | 保守・運用・翻訳・Steam / Microsoft Store 配布の手順 |

## ライセンス表記

フォント（Noto Sans JP、Yusei Magic、DotGothic16、Dela Gothic One）は SIL Open Font License 1.1（`assets/fonts/licenses/`）。
