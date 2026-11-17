# 設計書

引き継ぐ人（依頼者・Opus など）が、コードを読む前に全体をつかむための資料。仕様の数値は [SPEC.md](SPEC.md)。

## 1. 技術の選定と理由

| 項目 | 選定 | 理由 |
|---|---|---|
| エンジン | Godot 4.5（GDScript） | 無料・Windows出力が標準・3DとUIを1つで賄える・Steam配布実績が多い（要件#4） |
| 3D | プリミティブの手続き生成 | 外部モデルなしで完結。見た目の調整がコードの数値でできる |
| シーン構成 | `scenes/main.tscn` は空ノード1つ。全ノードをコードで生成 | エディタなしでも差分レビューと引き継ぎができる |
| LLM | Claude Messages API を HTTPRequest で直接呼ぶ | GDScript 用の公式SDKが無いため生HTTP |
| フォント | Noto Sans JP（同梱） | Godot標準フォントに日本語が無い。Steam Deck等でも同じ表示にする |

## 2. ファイル構成と責務

```
project.godot            プロジェクト設定（メインシーン、オートロード、既定フォント、ウィンドウ）
export_presets.cfg       Windows出力設定（exeにpck埋め込み）
scenes/main.tscn         ルートノード（main.gd を付けただけ）
scripts/
  main.gd                司令塔。3D・カメラ・お客さんキャラ・各画面。モード向けAPIを提供
  hud.gd                 プレイ中の画面（ゲージ、吹き出し、入力欄）。ルールは持たない
  solo_game.gd           1人用モードのルールと進行
  llm_client.gd          Claude API 呼び出し（お客さん生成・採点・接続テスト）
  offline_judge.gd       キーワード採点（台本モードとAI失敗時）
  scenarios.gd           台本のお客さんデータ（コンビニ8人・ゲームセンター8人）
  game_settings.gd       設定とハイスコアの保存（オートロード名 GameSettings）
  sfx.gd                 効果音をコードで合成して再生
  ui_kit.gd              UI部品（色、パネル、ボタン、ゲージ）の共通関数
  arcade_stage.gd        ゲームセンターの3D（クレーンゲーム）
  stage_world.gd         ステージ切替とコンビニの3D        ← サブエージェント作成中（HANDOVER参照）
  customer_character.gd  お客さんの3Dキャラと表情アニメ    ← 同上
assets/fonts/            Noto Sans JP（Medium / ExtraBold）と OFL.txt
.github/workflows/build.yml   インポート→自動プレイ→Windows出力
docs/                    本資料群
```

依存の向き: `main.gd` → 各スクリプト（preload）。`solo_game.gd` は `main` と `hud` を **型なしの変数** で受け取り、メソッドを直接呼ぶ（循環preloadを避けるため）。`class_name` は main 側からは使わず、すべて `preload` 定数で参照する（`.godot` のクラスキャッシュが無い状態でも動かすため）。

## 3. main.gd がモードに提供するAPI

| 関数・変数 | 役割 |
|---|---|
| `set_stage(stage_id)` | ステージ3Dを作り直す |
| `await spawn_customer(look)` | お客さんを入口から歩かせ、到着まで待つ |
| `await dismiss_customer(mood)` | 退店させ、出ていくまで待つ（happy / angry / smug） |
| `await customer_say(speaker, text)` | 吹き出しに1文字ずつ表示（口パク連動） |
| `customer_react(kind)` | calm / angry / explode / happy / smug の一発アニメ |
| `shake(strength)` | カメラを揺らす |
| `display_anger` (0〜100) | 表情・震え・照明の赤みに毎フレーム反映される |
| `sfx`, `llm`, `smoke` | 効果音、APIクライアント、自動テスト中かどうか |

対戦モードを足すときは `solo_game.gd` と同じ形の `versus_game.gd` を作り、このAPIと `hud.gd` を使う。

## 4. 3D側の約束（インターフェース）

`stage_world.gd`（Node3D）: `label_font` 変数、`build(stage_id)`、`get_customer_stand() -> Vector3`、`get_customer_entrance() -> Vector3`、`set_tension(t: 0..1)`。
`arcade` のときは `arcade_stage.gd` を子として生成し `build()` を呼び、`set_tension` を転送する。照明と WorldEnvironment は各ステージが自分で作る（カメラは main が作る）。

`customer_character.gd`（Node3D）: シグナル `arrived` / `left`、`setup(look)`、`set_anger(ratio: 0..1)`、`enter(from, to)`、`leave(to, mood)`、`talk(duration)`、`react(kind)`、`get_head_position()`。`leave` の後の `queue_free` は main が行う。

`arcade_stage.gd` の作り:
- メッシュ4種（箱・球・円柱・円錐）を使い回し、マテリアルは `_mat()` で色・発光・質感ごとにキャッシュ（描画のまとめ処理のため）。点滅させるマテリアルだけ `_new_mat()` で個別に作る。
- `_crane()` が1台を作る。`detailed=true` の台（カメラから近い島と左手前）は、ぬいぐるみに腹・手足・ほっぺを付ける。
- `_process` でアーム（左右・前後・ときどき降下して爪を閉じる）、ボタンとランプの点滅、吊りPOPの揺れ、緊張時の赤い明滅を動かす。
- 乱数は固定シード（毎回同じ配置）。

## 5. 1人用モードの流れ（solo_game.gd）

```
start(stage) ─ 4回くり返し ─ _play_customer()
  1. お客さんを用意: AIが使えるなら generate_customer、失敗/未設定なら台本から1人
  2. spawn_customer → 最初のクレームを表示
  3. ループ:
       入力を有効化（この間だけ _process が怒りを上げる）
       await _reply   … 返事（hud.reply_submitted 経由）または時間切れ（空文字）
       採点 _judge()  … AIのお客さん=judge_turn、失敗時と台本=offline_judge
       ゲージ更新 → お客さんの返事を表示 → 終了条件を判定
  4. 得点 → 退店 → 次のお客さん
finished(stage_id, results, total) を発行 → main が結果画面を出す
```

中断の仕組み: `_run`（通し番号）を `await` の前後で比べ、タイトルへ戻った後に古い処理が再開しても何もせず抜ける。新しい `await` を足したら、直後に必ず `if my_run != _run: return` を入れること。

## 6. LLM呼び出しの設計（llm_client.gd）

- `_post()` → `_request()`。1リクエストごとに HTTPRequest ノードを作って捨てる（同時呼び出しで衝突しない）。
- 返り値は辞書。失敗は `{"error": "日本語の説明"}`。呼び出し側は必ず `has("error")` を見る。
- 出力はJSONスキーマで固定し、受け取った値はコード側でも範囲を切り詰める（`clampi` 等）。
- お客さんが毎回変わるよう、人物の方向性（`PERSONALITIES`）をコード側で乱数選択して渡す。
- 会話履歴は1つのユーザーメッセージにまとめて渡す（短いのでキャッシュは使っていない）。

## 7. 自動テスト

`godot --headless -- --smoke` で、台本モードのまま全ステージを8倍速で自動プレイする（`main.gd` の `_run_smoke`、`solo_game.gd` の `_smoke_autoplay`）。お客さん4人で「良い返事／暴言／無言（時間切れ）／屈服」の4通りを通す。成功で `SMOKE OK` を出して終了コード0、150秒で `SMOKE TIMEOUT`。CIはログに `SCRIPT ERROR` / `Parse Error` があれば失敗にする。

## 8. 既知の設計上の注意

- APIキーは平文保存。配布前に暗号化保存（`ConfigFile.save_encrypted_pass`）などを検討する。
- レーティングをPC内保存にすると改ざんできる（SPEC 6節）。
- BGMは無い（効果音のみ）。
- 文字の折り返しは「任意位置」で行っている（禁則処理なし）。
