# 設計書

引き継ぐ人（依頼者・Opus など）が、コードを読む前に全体をつかむための資料。仕様の数値は [SPEC.md](SPEC.md)、サーバーの詳細は [SERVER.md](SERVER.md)、画面の見た目の決まりは [UI_GUIDE.md](UI_GUIDE.md)。

## 1. 全体像

```
┌────────── Windows のゲーム（Godot 4.5）──────────┐         ┌──────── ゲームサーバー（Node.js）────────┐
│ main.gd ── 画面・3D・カメラ                       │  HTTP   │ http.ts  1人用API・アカウント・ランキング  │
│   ├ solo_game.gd   1人用のルール ───────────────┼────────▶│ llm.ts   Claude API（APIキーはここだけ）   │
│   ├ versus_game.gd 対戦の表示と入力 ─────────────┼── WS ──▶│ ws.ts → lobby.ts（マッチング・部屋）       │
│   ├ server_api.gd  HTTP / WebSocket              │         │          match.ts（対戦の進行・判定）      │
│   ├ voice.gd       録音・再生                     │         │ stt.ts   文字起こし（別サーバー）          │
│   ├ llm_client.gd  自分のキーで直接（予備）        │         │ db.ts    SQLite（レーティング・記録）      │
│   └ offline_judge.gd 台本＋キーワード判定（予備） │         └───────────────────────────────────────┘
└──────────────────────────────────────────────────┘
          共通のデータ: data/scenarios*.json（台本）・data/judge_words.json（判定語）
```

- 1人用は、既定でサーバーに問い合わせる。サーバーが無くても、台本と自分のキーで遊べる（予備）。
- 対戦は必ずサーバー経由。クライアントは入力を送り、サーバーからのメッセージを画面に映すだけ（改ざん防止）。

## 2. 技術の選定と理由

| 項目 | 選定 | 理由 |
|---|---|---|
| ゲーム | Godot 4.5（GDScript） | 無料・Windows出力が標準・3DとUIを1つで賄える（要件#4） |
| 3D | プリミティブの手続き生成 | 外部モデル不要。見た目の調整がコードの数値でできる |
| シーン | `scenes/main.tscn` は空ノード1つ。全部コードで作る | エディタなしでも差分レビュー・引き継ぎができる |
| サーバー | Node.js 22 + TypeScript（型除去で直接実行） | 公式 Anthropic SDK が使える。ビルド工程が無く運用が簡単 |
| 通信 | HTTP（1人用）と WebSocket（対戦） | 対戦はサーバーから押し出す通知が多いため WebSocket |
| DB | `node:sqlite` | 追加の依存なし。1台のサーバーで十分な規模 |
| 音声 | 押して話す＋μ-law で送る＋サーバーで文字起こし | 判定に文字が必要。常時の音声通話より作りが単純で、通信量も小さい |
| 翻訳 | Godot の TranslationServer に JSON から訳を登録 | 日本語の文がそのままキー。訳漏れを `tools/i18n.py` で機械的に検出できる |

## 3. クライアントのファイル

```
scripts/
  main.gd             司令塔。3D・カメラ・お客さんキャラ、各画面（タイトル／設定／遊び方／休憩／レシート／ロビー）、自動テスト
  hud.gd              プレイ画面（メモ・付箋・レジ表示器・フキダシ・記入欄・押して話す）。ルールは持たない
  solo_game.gd        1人用のルールと進行。AIの使い方（server / own_key / offline）を切り替える
  versus_game.gd      対戦の表示と入力。サーバーのメッセージ（SERVER.md 5節）を画面に映す
  server_api.gd       サーバーとの通信（HTTP、WebSocket、ログイン、自動再接続）
  voice.gd            マイク録音（押している間）、μ-law 変換、相手の声の再生
  llm_client.gd       自分のAPIキーで Claude を直接呼ぶ（予備）
  offline_judge.gd    キーワード判定（予備。サーバーと同じ規則）
  scenarios.gd        台本の読み込み（言語別）
  game_settings.gd    設定・ログイン情報・言語の切替（オートロード GameSettings）
  ui_kit.gd           色・書体・紙・ボタン・入力欄の共通関数（UI_GUIDE の決まりをコードにしたもの）
  ui_paper.gd         自前で描く部品: フキダシ、引き継ぎメモ、レジ表示器、レシート
  sfx.gd              効果音をコードで合成
  stage_world.gd      ステージ切替とコンビニの3D（Opus下書き）
  arcade_stage.gd     ゲームセンターの3D（クレーンゲーム）
  customer_character.gd お客さんの3Dキャラと表情（Opus下書き）
data/
  scenarios.json / scenarios.en.json   台本（サーバーと共通）
  judge_words.json                      キーワード判定の語（サーバーと共通）
  i18n/en.json                          画面の文言の英訳（日本語の文 → 英語）
tools/i18n.py          翻訳キーの抽出と訳漏れ検査
packaging/             Microsoft Store（MSIX）と Steam の配布設定
server/                ゲームサーバー（SERVER.md）
```

依存の向き: `main.gd` → 各スクリプト（`preload`）。ゲームモードは `main` と `hud` を**型なし変数**で受け取り、メソッドを直接呼ぶ（循環 preload を避ける）。`class_name` には頼らず `preload` 定数で参照する。

## 4. main.gd がゲームモードに提供するもの

| 関数・変数 | 役割 |
|---|---|
| `set_stage(id)` / `enter_versus(id)` | ステージ3Dを作る / 対戦用に画面を用意する |
| `await spawn_customer(look)` / `await dismiss_customer(mood)` | お客さんの入店・退店（終わるまで待てる） |
| `await customer_say(speaker, text, angry)` | フキダシに1文字ずつ（angry でギザギザ） |
| `customer_react(kind)` / `shake(strength)` | 一発の反応アニメ / カメラの揺れ |
| `display_anger` | 0〜100。表情・震え・照明の赤みに毎フレーム反映 |
| `mode` | `"solo"` / `"versus"` / `""`。入力の送り先の判断に使う |
| `sfx`, `llm`, `api`, `smoke` | 効果音、自分のキー用クライアント、サーバー通信、自動テスト中か |

画面（HUD）は言語を変えたときに作り直すので、ゲームモードは `attach_hud(hud)` で付け替えられるようにしてある。

## 5. 1人用の流れ（solo_game.gd）

```
start(stage) ─ 4回くり返し ─ _play_customer()
  1. _prepare_customer(): server → /solo/start、own_key → generate_customer、どれも失敗なら台本
  2. spawn_customer → 最初のクレーム
  3. ループ: 入力を有効化（この間だけ怒りが上がる）→ await _reply（返事 or 時間切れ）
            → _judge()（server → /solo/turn / own_key → judge_turn / 予備 → offline_judge）
            → ゲージ更新 → お客さんの返事 → 終了判定
  4. 得点 → 退店
finished(stage, results, total) → main がレシートを出す
```

中断: `_run`（通し番号）を `await` の前後で比べ、タイトルに戻った後に古い処理が再開しても抜ける。**`await` を足したら直後に `if my_run != _run: return` を入れる。**

## 6. 対戦の流れ

### サーバー（match.ts）
`run()` → 2ラウンドの `playRound()`。入力待ちは `waitInput(seat, phase, seconds)`（タイマーか、`onSay` / `onVoice` で解決する Promise）。
店員の番の怒りは「開始時の怒り + rate × 経過時間」で、入力が届いた時点の値を計算する。`TIME_SCALE` でテスト時に時間を縮める。
切断は `onDisconnect`（20秒の猶予）→ 戻れば `onReconnect` で状態を送り直す（`match_found` → `round_start` → これまでのセリフ → `phase`）。

### クライアント（versus_game.gd）
`request(kind, format)` → ログイン → WebSocket を開く → `hello` を受けたら `queue` / `room_create` / `room_join` を送る。
以後はメッセージごとの関数（`_on_round_start` など）で画面を更新するだけ。店員の番は、受け取った `anger` と `rate` から手元で怒りを上げて見せる（正しい値はサーバーが `judged` で送る）。

### 音声
`hud` の「押して話す」→ `voice.start_recording()`（マイク → AudioEffectCapture）→ 離す → 16kHz に間引き → μ-law → base64 で `voice` メッセージ。
相手の声は `voice` メッセージで届き、μ-law → 16bit → AudioStreamWAV で再生。

## 7. 多言語

- 画面の文言は日本語の文をそのまま書き、表示するときに `tr("…")` を通す（Label などは自動で訳される）。訳は `data/i18n/en.json`。
- 文言を足したら `python3 tools/i18n.py check` を実行し、出てきた文の英訳を `en.json` に足す（CIでも検査）。
- 台本・判定語・AIの出力・コメントは言語ごとのデータを使う（サーバーは `lang` を受け取る）。

## 8. 自動テストと画面確認

| 何を | どうやって |
|---|---|
| サーバーの単体・結合テスト（17件） | `cd server && npm test`（実際に WebSocket で2人を対戦させる） |
| 翻訳の漏れ | `python3 tools/i18n.py check` |
| 1人用を最後まで | `godot --headless -- --smoke --source=offline`（台本）／ `--source=server --server=URL`（サーバー経由） |
| 対戦を最後まで | `godot --headless -- --vs-smoke=text --profile=A --server=URL` を2つ同時に（`voice` も） |
| 見た目 | `godot -- --shots --lang=ja`（`docs/screenshots/` に保存）。CIはコミットメッセージに `[shots]` があると撮って自動コミット |

CI（`.github/workflows/build.yml`）は、サーバーのテスト → サーバーを起動して上の自動プレイ4種 → Windows 出力 → MSIX 作成、の順に行う。

## 9. 既知の設計上の注意

- 自分のAPIキーはPCに平文保存。暗号化保存（`ConfigFile.save_encrypted_pass`）を検討。
- サーバーの1人用セッションと対戦はメモリ上。サーバーを再起動すると進行中のものは消える（レーティングと記録はDBに残る）。サーバーを複数台にする場合は作り直しが要る。
- 音声の文字起こしは外部サービスに頼る（SERVER.md 3節）。
- ゲストのアカウントはトークンを失うと戻せない（設定ファイルを消すと別人になる）。
- BGM は無い（効果音のみ）。
