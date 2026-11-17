# ゲームサーバー（server/）

要件#24「サーバーにAPIキーを登録し、クライアントはサーバーに問い合わせてゲームを進めるのを既定にする」のためのバックエンド。
1人用のAI（お客さんの生成と採点）と、対戦のすべて（マッチング・部屋・進行・判定・時間・レーティング）を受け持つ。

- 言語: Node.js 22.18 以上 + TypeScript（Node の型除去で `.ts` を直接実行。ビルド工程なし）
- 依存: `@anthropic-ai/sdk`（公式SDK）、`ws`（WebSocket）、`zod`（AIの出力の検証）。DBは Node 標準の SQLite（`node:sqlite`）
- 置き場所: `server/src/`。テストは `server/test/`

## 1. 動かし方

```bash
cd server
```

```bash
npm ci
```

```bash
ANTHROPIC_API_KEY=sk-ant-... npm start
```

`http://127.0.0.1:8787` で待ち受ける。キーが無いと、AIの代わりにキーワード判定で動く（遊べるが単調）。

テスト（AIなし・音声はモック・時間25倍速で、実際に2人を対戦させる）:

```bash
npm test
```

```bash
npm run typecheck
```

Docker（リポジトリのルートで）:

```bash
ANTHROPIC_API_KEY=sk-ant-... docker compose -f server/compose.yaml up -d --build
```

クライアントの接続先は、設定画面の「サーバーのURL」、または配布版の既定値 `scripts/game_settings.gd` の `DEFAULT_SERVER_URL`。**本番のサーバーを用意したら、この既定値を書き換えてから exe を作る。**

## 2. 環境変数

| 名前 | 既定 | 意味 |
|---|---|---|
| `ANTHROPIC_API_KEY` | なし | Claude API のキー。**サーバーにだけ置く**（クライアントには渡らない） |
| `CLAUDE_MODEL` | `claude-haiku-5-5` | 使うモデル（要件#33。サーバーは Haiku だけを提供） |
| `LLM_MODE` | `auto` | `auto`=キーがあればAI / `claude`=必ずAI / `offline`=使わない |
| `LLM_TIMEOUT_MS` | 45000 | AIの応答待ちの上限 |
| `LLM_PER_MINUTE` | 20 | 1人のプレイヤーが1分間に使えるAI呼び出し回数（運営の料金を守る。超えるとキーワード判定） |
| `STT_PROVIDER` | `none` | 音声の文字起こし。`none` / `openai_compatible` / `whisper_cpp` / `mock`（テスト用） |
| `STT_URL` | `http://127.0.0.1:8080` | 文字起こしサーバーのURL |
| `STT_MODEL` | `whisper-1` | `openai_compatible` のときのモデル名 |
| `STT_API_KEY` | なし | 文字起こしサーバーに鍵が要るとき |
| `PORT` / `HOST` | 8787 / 0.0.0.0 | 待ち受け |
| `DB_PATH` | `server/var/cushara.db` | SQLite のファイル |
| `SCENARIOS_PATH` | `data/scenarios.json` | 台本（英語は同じ場所の `scenarios.en.json`、判定語は `judge_words.json`） |
| `GUESTS_PER_HOUR` | 20 | 1つのIPから1時間に作れるアカウント数 |
| `TRUST_PROXY` | なし | `1` ならリバースプロキシの `X-Forwarded-For` を信じる |
| `VS_*` / `MM_ANYONE_AFTER_SEC` | | 対戦の秒数・マッチングの設定（`src/config.ts`） |
| `TIME_SCALE` | 1 | テスト用に時間を速める倍率 |
| `ALLOW_RANKED_ROOMS` | `1` | EOS で組んだ部屋をランクマッチにしてよいか（`0` で禁止） |
| `RANKED_ROOM_MAX_GAP` | 400 | ランクの部屋に入れるレート差の上限 |
| `ALLOW_SAME_IP_RANKED` | `0` | `1` なら同じIPどうしでもランクマッチを組む（テスト用。本番は `0`） |
| `SAME_PAIR_LIMIT_24H` | 3 | 同じ2人が24時間に何試合までレーティングを動かせるか |

本番では、前に HTTPS 終端（Caddy、nginx など）を置き、`wss://` で WebSocket を通すこと。

## 3. 音声対戦（文字起こし）

声は「押して話す」間だけ録音し、16kHz・モノラル・8bit μ-law（G.711）で送る。サーバーは
1. すぐに相手へ声を中継する（ボイスチャットとして聞こえる）
2. 16bit WAV に戻して文字起こしサービスに送り、文字にして判定する

文字起こしは別のサーバーとして用意する（このリポジトリには入っていない）。
- `whisper_cpp`: whisper.cpp 付属の `whisper-server`（`POST /inference`）
- `openai_compatible`: OpenAI 互換の `POST /v1/audio/transcriptions` を持つもの（faster-whisper 系など）

`STT_PROVIDER=none` のとき、サーバーは音声対戦を受け付けず、クライアントのロビーで「声で言い合う」が押せなくなる。
**実際の文字起こしサーバーとつないだ確認はまだしていない**（CIは `mock`）。

## 4. HTTP API

すべて JSON。ログインが要るものは `Authorization: Bearer <token>`。エラーは `{"error": {"code", "message"}}`（message は日本語）。

| メソッド・パス | ログイン | 内容 |
|---|---|---|
| `GET /healthz` | | 生存確認 |
| `GET /api/v1/info` | | `{version, ai, voice, langs, rules, online}` |
| `POST /api/v1/guest` | | `{name}` → `{token, player}`。ゲストのアカウントを作る（トークンはサーバーにはハッシュで保存） |
| `GET /api/v1/me` | 要 | `{player}`（名前・レーティング・ランク名・勝敗） |
| `POST /api/v1/me` | 要 | `{name}` → 名前を変える |
| `GET /api/v1/leaderboard?limit=50` | | 対戦したことのある人のレーティング順 |
| `POST /api/v1/solo/start` | 要 | `{stage, avoid, lang, event?}` → `{session_id, source, notice, event, customer}`。お客さんを作る（AI。失敗・上限なら台本）。`event: "wild"` で要注意人物（ネタ枠から選ぶ・AIには突飛な人物を頼む。要件#52） |
| `POST /api/v1/solo/hint` | 要 | `{session_id}` → `{keyword, action}`。店長のアドバイス（解決の方向の言葉1つと、効く行動ボタン1つ）。1人のお客さんにつき1回（2回目は 409） |
| `POST /api/v1/solo/turn` | 要 | `{session_id, reply, anger, resolve}` → `{anger_delta, resolve_delta, yielded, customer_reply, comment, judged_by, notice}` |

`customer` には採点用のキーワードを入れない（答えが分からないように）。会話の履歴はサーバーが持つ（クライアントが送ってきた履歴は使わない）。

## 5. WebSocket（`/ws`）のメッセージ

すべて `{"t": "<種類>", ...}` の JSON。接続したら最初に `auth` を送る（10秒以内）。

### クライアント → サーバー
| t | 中身 | 意味 |
|---|---|---|
| `auth` | `token`, `lang` | ログイン。試合中に切れていたら、その試合に戻る |
| `lang` | `lang` | 言語を変える（`ja` / `en`） |
| `queue` | `format` | ランクマッチに並ぶ（`text` / `voice`） |
| `cancel` | | 並ぶのをやめる・部屋を閉じる |
| `room_create` | `format` | フレンド部屋を作る |
| `room_join` | `code` | 部屋に入る（大文字小文字は区別しない） |
| `say` | `text` | 自分の番の文字のセリフ（200文字まで） |
| `voice` | `audio`（base64 μ-law）, `debug_text`（mock のときだけ使う） | 自分の番の声（0.1〜20秒） |
| `leave` | | 試合をやめる（相手の勝ち） |

### サーバー → クライアント
| t | 主な中身 |
|---|---|
| `hello` | `player`, `resumed` |
| `queued` / `queue_status` | `seconds`, `range`（許容レーティング差。null は誰とでも）, `waiting_players` |
| `room_created` / `room_expired` | `code` |
| `match_found` | `match_id`, `kind`（ranked/friend）, `format`, `lang`, `stage`, `rounds`, `you`, `opponent` |
| `round_start` | `round`, `role`（staff/customer）, `card`（お客さんの設定）, `anger`, `resolve`, `rate`, `totals` |
| `phase` | `phase`（customer_turn / staff_turn / judging / intro / round_end）, `turn`（you/opponent/none）, `seconds`, `elapsed`, `anger`, `resolve`, `rate` |
| `line` | `role`, `by`, `text`, `via`（text/voice） |
| `voice` | `role`, `by`, `audio`（相手の声） |
| `judged` | `anger`, `resolve`, `anger_delta`, `resolve_delta`, `comment`, `about` |
| `round_end` | `outcome`, `winner`, `points`, `totals` |
| `match_end` | `result`（win/lose/draw）, `reason`, `kind`, `you_points`, `opponent_points`, `rating_before`, `rating_after`, `rating_delta`, `rank` |
| `opponent_status` | `connected`, `grace_seconds` |
| `notice` / `error` | `text` / `code`, `message` |

## 6. 中の作り

| ファイル | 役割 |
|---|---|
| `main.ts` | 起動 |
| `config.ts` | 環境変数 |
| `http.ts` | HTTP API と1人用のセッション（メモリ上、30分で消える） |
| `ws.ts` | WebSocket の受け口、送りすぎの制限、ping |
| `lobby.ts` | ランクマッチの待ち行列（0.5秒ごとに組む）とフレンド部屋（15分で期限切れ） |
| `match.ts` | 1試合の進行（サーバーが時間と判定を持つ）、切断の猶予（20秒）、結果の記録 |
| `llm.ts` | Claude API（お客さん生成・店員の採点・客役の採点）。構造化出力・拒否時のフォールバック・ゲーム外の依頼対策 |
| `keyword_judge.ts` | キーワード判定（AIが使えないとき） |
| `stt.ts` / `audio.ts` | 文字起こし / μ-law と WAV の変換 |
| `db.ts` / `rating.ts` | SQLite（players / matches）、Elo とランク名 |
| `scenarios.ts` / `lang.ts` | 台本の読み込み / 対応言語 |

### AIの使い方の注意
- モデルは `CLAUDE_MODEL`。Opus 5.5 / Sonnet 5.5 / Fable 系のときは、拒否されたら別モデルで自動でやり直す設定（`fallbacks: "default"`、ベータ `server-side-fallback-2026-07-01`）を付ける。
- 出力は JSON スキーマで固定し（SDK の `zodOutputFormat`）、受け取った値はさらに範囲を切り詰める。
- **ゲーム外の依頼（要件#28）**: 指示文で「役を崩さない・コードやモデル名などに答えない」と決め、さらに出力にコード・AI/モデル名・URL などが混ざっていたら捨てて台本のセリフに差し替える（`leaksMeta`）。キーワード判定も、そうした返答を「的外れ」として怒りを上げる（`isOffTopic`）。
- 料金を守るため、プレイヤーごとに1分あたりの回数制限がある（`LLM_PER_MINUTE`）。

### データの保存
- `players`: id, トークンのハッシュ, 名前, レーティング, 勝敗数。
- `matches`: 対戦ごとの結果とレーティングの増減、終わり方（completed / left / disconnected）。
- ランクマッチの結果だけがレーティングと勝敗数を変える。フレンド対戦は記録だけ。
- バックアップは `DB_PATH` のファイル（と `-wal`）をコピーする。

## 7. チート対策（要件#47）

| 狙われること | 対策 | 場所 |
|---|---|---|
| 判定・時間・点数の改ざん（対戦） | もともと全部サーバーが決める。クライアントは入力を送るだけ | `match.ts` |
| 2つのアカウントで自分と組んでレーティングを稼ぐ | 同じIPどうしはランクマッチで組まない・ランクの部屋に入れない（`same_network`） | `lobby.ts` |
| 同じ相手と何度も組む（談合） | 24時間に同じ2人で `SAME_PAIR_LIMIT_24H` 試合を超えたらレーティングを動かさない（`rating_note: same_pair`） | `match.ts` `db.ts` |
| すぐに抜けて相手に勝ちを渡す | 抜けた側が一度も入力していなければ、勝った側のレーティングも動かさない（`rating_note: early_leave`） | `match.ts` |
| EOS の部屋で好きな相手を選ぶ | ランクの部屋はレート差 `RANKED_ROOM_MAX_GAP` 以内だけ | `lobby.ts` |
| 1人用の点数の改ざん | 1人用もサーバーが会話ごとに怒り・納得を持ち、納得はサーバーの値だけ、怒りは大きい方を採る。決着後の入力は 409 | `http.ts` |
| AI の使いすぎ（運営の料金） | 1人あたり1分の上限（`LLM_PER_MINUTE`）。超えたらキーワード判定 | `ratelimit.ts` |
| 変な値（答える時間・件数など） | 決まった値以外は既定値にする（`Object.hasOwn` で確認） | `lobby.ts` `http.ts` |

クライアント（ゲーム）側は改造できる前提なので、レーティングと点数に効くことはすべてサーバーで決める。

