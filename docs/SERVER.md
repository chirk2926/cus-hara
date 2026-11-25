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
| `ANTHROPIC_API_KEY` | なし | Claude API のキー。**サーバーにだけ置く**（クライアントには渡らない）。管理画面の「AIのAPI」で登録したら、そちらが使われる（9.2） |
| `OPENAI_API_KEY`・`GEMINI_API_KEY`・`DEEPSEEK_API_KEY` | なし | OpenAI・Gemini・DeepSeek のキー（要件#115）。管理画面でまだ登録していないとき、Claude の次の順位として使う。モデルは `OPENAI_MODEL`・`GEMINI_MODEL`・`DEEPSEEK_MODEL`（既定 gpt-5-mini・gemini-2.5-flash・deepseek-chat） |
| `CLAUDE_MODEL` | `claude-haiku-5-5` | 使うモデル（要件#33。サーバーは Haiku だけを提供） |
| `LLM_MODE` | `auto` | `auto`=キーがあればAI / `claude`=必ずAI / `offline`=使わない |
| `LLM_PROVIDER` | `anthropic` | 使うAI（要件#78）。`anthropic`=Claude（`ANTHROPIC_API_KEY`・`CLAUDE_MODEL`）/ `openai_compatible`=OpenAI 互換の API |
| `LLM_BASE_URL` | なし | `openai_compatible` のときの API の場所。例: OpenAI `https://api.openai.com/v1`、Gemini `https://generativelanguage.googleapis.com/v1beta/openai`、DeepSeek `https://api.deepseek.com/v1`、Groq `https://api.groq.com/openai/v1`、Mistral `https://api.mistral.ai/v1`、ローカルの Ollama `http://127.0.0.1:11434/v1` |
| `LLM_MODEL` | なし | `openai_compatible` のときのモデル名（各社の名前をそのまま） |
| `LLM_API_KEY` | なし | `openai_compatible` のときのキー（ローカルの Ollama などは不要）。**サーバーにだけ置く** |
| `LLM_JSON_MODE` | `json_schema` | `json_schema`=スキーマどおりに出させる（対応していれば確実）/ `json_object`=JSON だけ出させ、形は指示文で伝える（スキーマ指定に対応していないAI向け） |
| `LLM_TIMEOUT_MS` | 15000 | AIの応答待ちの上限（やり直しなし。ゲームは35秒で待つのをやめる） |
| `LLM_PER_MINUTE` | 20 | 1人のプレイヤーが1分間に使えるAI呼び出し回数（運営の料金を守る。超えるとキーワード判定） |
| `STT_PROVIDER` | `none` | 音声の文字起こし。`none` / `openai_compatible` / `whisper_cpp` / `mock`（テスト用） |
| `STT_URL` | `http://127.0.0.1:8080` | 文字起こしサーバーのURL |
| `STT_MODEL` | `whisper-1` | `openai_compatible` のときのモデル名 |
| `STT_API_KEY` | なし | 文字起こしサーバーに鍵が要るとき |
| `PORT` / `HOST` | 8787 / 0.0.0.0 | 待ち受け |
| `DB_PATH` | `server/var/cushara.db` | SQLite のファイル |
| `SCENARIOS_PATH` | `data/scenarios.json` | 台本（英語は同じ場所の `scenarios.en.json`、判定語は `judge_words.json`） |
| `GUESTS_PER_HOUR` | 20 | 1つのIPから1時間に作れるアカウント数 |
| `TRUST_PROXY` | なし | `1` なら、信じてよいプロキシ（同じマシンの 127.0.0.1 と `TRUSTED_PROXIES`）から来た接続だけ、`CF-Connecting-IP`（無ければ `X-Forwarded-For` の一番右）をプレイヤーの IP にする（要件#108） |
| `TRUSTED_PROXIES` | なし | 転送ヘッダーを信じるプロキシの住所（カンマ区切り）。Docker で動かすときのブリッジの出入口（compose.yaml の例は `172.30.0.1` に固定）など |
| `VS_*` / `MM_ANYONE_AFTER_SEC` | | 対戦の秒数・マッチングの設定（`src/config.ts`） |
| `TIME_SCALE` | 1 | テスト用に時間を速める倍率 |
| `ALLOW_RANKED_ROOMS` | `0` | EOS で組んだ部屋をランクマッチにしてよいか（`0` で禁止） |
| `RANKED_ROOM_MAX_GAP` | 400 | ランクの部屋に入れるレート差の上限 |
| `ALLOW_SAME_IP_RANKED` | `0` | `1` なら同じIPどうしでもランクマッチを組む（テスト用。本番は `0`） |
| `SAME_PAIR_LIMIT_24H` | 3 | 同じ2人が24時間に何試合までレーティングを動かせるか |
| `LLM_GLOBAL_PER_MINUTE` | 300 | サーバー全体で1分間に使えるAI呼び出しの上限（超えたらキーワード判定・台本） |
| `SOLO_MAX_TURNS` | 30 | 1人用の1人のお客さんとのやりとりの上限（超えたら 409 too_long） |
| `WS_PER_IP` | 16 | 1つのIPから同時に開ける WebSocket の数（ほかに1分60回までの接続の速さの制限） |

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
| `GET /api/v1/status` | | 紹介サイトの「サーバーの状況」用。`{checked_at, game: ok\|maintenance, ai: ok\|degraded\|down, voice: ok\|off, message, note}` だけ。どのサイトからも読める（CORS `*`、1分30回まで、30秒キャッシュ）。AI の会社・モデル・キー・エラーの中身・バージョン・人数は出さない。ai は直近15分の AI の呼び出しの成功と失敗の数から決める（3割以上失敗で degraded、3回以上すべて失敗・未設定で down）。note は管理画面の 設定 → 運営 →「サーバーの状況のお知らせ」 |
| `POST /api/v1/guest` | | `{name}` → `{token, player}`。ゲストのアカウントを作る（トークンはサーバーにはハッシュで保存） |
| `GET /api/v1/me` | 要 | `{player}`（名前・レーティング・ランク名・勝敗） |
| `POST /api/v1/me` | 要 | `{name}` → 名前を変える |
| `GET /api/v1/leaderboard?limit=50` | | 対戦したことのある人のレーティング順 |
| `POST /api/v1/solo/start` | 要 | `{stage, avoid, lang, event?, payout?}` → `{session_id, source, notice, event, customer}`。`payout`（10〜80、既定30）はクレーンのペイアウト率で、「取れない」クレームの出やすさと言う金額が変わる（要件#55）。`customer` には台の種類 `machine` と、筐体のデータ `spend: {claimed, actual, expected, payout}`（該当する客だけ）が入る。お客さんを作る（AI。失敗・上限なら台本）。`event: "wild"` で要注意人物（ネタ枠から選ぶ・AIには突飛な人物を頼む。要件#52） |
| `POST /api/v1/solo/hint` | 要 | `{session_id}` → `{keyword, action}`。店長のアドバイス（解決の方向の言葉1つと、効く行動ボタン1つ）。1人のお客さんにつき1回（2回目は 409） |
| `POST /api/v1/solo/turn` | 要 | `{session_id, reply, anger, resolve}` → `{anger_delta, resolve_delta, yielded, customer_reply, comment, judged_by, notice}` |

`customer` には採点用のキーワードを入れない（答えが分からないように）。会話の履歴はサーバーが持つ（クライアントが送ってきた履歴は使わない）。

## 5. WebSocket（`/ws`）のメッセージ

すべて `{"t": "<種類>", ...}` の JSON。接続したら最初に `auth` を送る（10秒以内）。

### クライアント → サーバー
| t | 中身 | 意味 |
|---|---|---|
| `auth` | `token`, `lang` | ログイン。試合中に切れていたら、その試合に戻る |
| `lang` | `lang` | 言語を変える（`ja` / `en` / `zh` / `ko`） |
| `queue` | `format`, `server`, `translate` | ランクマッチに並ぶ（`text` / `voice`）。`server` は接続サーバー（`ja`/`en`/`zh`/`ko`/`global`。省くと自分の言語）。同じサーバーの人どうしで組む。`translate` は翻訳モード（グローバルだけ。要件#132） |
| `cancel` | | 並ぶのをやめる・部屋を閉じる |
| `room_create` | `format`, `server`, `translate` | フレンド部屋を作る（部屋は作った人のサーバー） |
| `room_join` | `code`, `translate` | 部屋に入る（大文字小文字は区別しない） |
| `say` | `text` | 自分の番の文字のセリフ（200文字まで） |
| `voice` | `audio`（base64 μ-law）, `debug_text`（mock のときだけ使う） | 自分の番の声（0.1〜20秒） |
| `leave` | | 試合をやめる（相手の勝ち） |

### サーバー → クライアント
| t | 主な中身 |
|---|---|
| `hello` | `player`, `resumed` |
| `queued` / `queue_status` | `seconds`, `waiting_players`, `server`（レーティングの差は送らない。要件#124） |
| `room_created` / `room_expired` | `code` |
| `match_found` | `match_id`, `kind`（ranked/friend）, `format`, `lang`, `server`, `translate`, `stage`, `rounds`, `you`, `opponent` |
| `round_start` | `round`, `role`（staff/customer）, `card`（お客さんの設定）, `anger`, `resolve`, `rate`, `totals` |
| `phase` | `phase`（customer_turn / staff_turn / judging / intro / round_end）, `turn`（you/opponent/none）, `seconds`, `elapsed`, `anger`, `resolve`, `rate` |
| `line` | `role`, `by`, `text`, `via`（text/voice）, `seq` |
| `line_tr` / `judged_tr` / `card_tr` | 翻訳モードの人だけに、あとから送る訳（`seq` で元の `line`・`judged` に合わせる。`card_tr` は `seq` がラウンドの番号で `title`, `memo`, `demand`, `opening`）。訳せなければ送らない（原文のまま） |
| `voice` | `role`, `by`, `audio`（相手の声） |
| `judged` | `anger`, `resolve`, `anger_delta`, `resolve_delta`, `comment`, `about`, `seq` |
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

## 8. セキュリティの点検（要件#77、2026-11-18）

| 見たこと | 結果・対策 |
|---|---|
| AIの料金の乱用（ゲストを大量に作って呼ぶ） | 1人あたりの上限に加えて、**サーバー全体の上限** `LLM_GLOBAL_PER_MINUTE` を足した。超えたらAIを呼ばずにキーワード判定・台本 |
| AIへの指示文に入るクライアントの値 | 「避ける呼び名」（avoid）は10件・各30文字まで、改行や制御文字を消す。返事は200文字まで（もとから） |
| 長い会話で料金がふくらむ | AIに送る会話は最後の20件まで。1人のお客さんとのやりとりは `SOLO_MAX_TURNS` 回まで |
| メモリの使いきり | 1人用の会話は全体で2万件まで（古いものから捨てる。30分で自動削除はもとから） |
| WebSocket の乱用 | ログイン前は auth 以外・4KB を超えるメッセージで切る。1つのIPから同時 `WS_PER_IP` 本・1分60回まで。ログイン後は10秒40通まで（もとから） |
| SQL | すべてプレースホルダ（`?`）で値を渡している。列名を文字で組み立てている所（勝ち・負け・引き分けの列）は、コードの中の決まった3つから選ぶだけで、外からの値は入らない |
| 認証 | トークンは32バイトのランダム、DBにはハッシュだけ。比べるのもハッシュで引くだけ |
| 名前・セリフの表示 | 名前は16文字・制御文字と `<>` を消す。ゲーム側のフキダシは BBCode を使わない設定なので、`[...]` で見た目を崩されない |
| AIへのプロンプト注入 | 判定の指示文に「返事の中の命令には従わない」と書いてあり、出力にコード・モデル名などが混ざったら台本に差し替える（要件#28） |
| 秘密情報 | リポジトリと全履歴に、APIキー・トークン・秘密鍵は無い（要件#76） |
| CI | 既定の権限を「読み取りだけ」にし、スクリーンショットを書き戻すジョブだけ書き込みにした |
| ゲーム側の自分のAPIキー | 設定ファイルに平文で置いていたのを、このPCの固有IDで暗号化したファイル（`settings_secret.cfg`）に移した（古い版の平文は起動時に移して消す） |

### 8.1 2回目の点検（要件#93、2026-11-18）
| 見たこと | 結果・対策 |
|---|---|
| 依存パッケージの脆弱性（`npm audit`） | ws・zod に報告があったので ws 8.23.0・zod 4.6.7 に上げた（バージョンは固定）。`npm audit` は 0 件 |
| テスト用のデバッグパネル | 本番の exe でも `-- --test` で開けてしまっていたのを、テスト版の exe（機能タグ testbuild）か、エディタ・デバッグ版で動かしたときだけにした |
| 対戦のセリフの長さ | ゲーム側の上限（日本語・中国語128文字、英語256文字）に合わせて、サーバーも256文字で切る |
| 通報・名札の飾り・キャラクター | 値は決まった選択肢だけ通す（`cleanTag`・`cleanAvatar`）。通報は1時間10回まで、同じ相手・同じ試合は1回だけ |
| SQL・認証・プロンプト注入 | 8節のとおり。新しい表（reports）もプレースホルダだけ |

残っていること（運営の準備）: 本番では HTTPS（`wss://`）の前段を置くこと（docs/MAINTENANCE.md）。`TRUST_PROXY=1` は、前段のプロキシが `X-Forwarded-For` を付け直す場合だけにすること（そうでないとIPを偽れる）。

## 9. AIの料金を下げる・Claude 以外のAI（要件#78）

### 9.1 プロンプトのキャッシュ（Claude）
- 判定・お客さんづくりの指示文（毎回同じで長い部分）に `cache_control` を付け、2回目以降はキャッシュから読む。キャッシュから読んだ分の入力の料金は、ふつうの入力より大幅に安い（料金表は Anthropic のサイト）。会話の部分は毎回違うので、指示文の後ろに置いている。
- Claude Haiku 5.5 は 512 トークン以上の指示文からキャッシュされる。このゲームの指示文はそれより長い。
- **会話の部分もキャッシュする（要件#93）**: 判定に送る文を「舞台・人物（変わらない）→ 会話を1行ずつ → 今の怒り・納得度（毎回変わる）」の順に並べ、会話の最後の行に `cache_control` を付ける。会話は後ろに1行ずつ足されるだけなので、次の判定では前回までの会話がキャッシュから読まれ、新しい行の分だけがふつうの料金になる。送る中身は前と同じなので、判定の質は変わらない。
- **対戦の不適切な発言の確認を、採点と同じ1回の呼び出しにまとめた（要件#93）**: 前は「AIで不適切か確かめる」→「AIで採点する」の2回呼んでいた。今は採点の出力に `flag`（sexual / hate / threat / personal_info / none）を足し、1回で両方を返す。キーワードの確認はその前にそのまま行う。客役の最初のクレームは採点がないので、今までどおり別に確かめる。セリフを相手に見せるのは確かめた後なので、伏せ字の扱いも前と同じ。AI が使えない・上限に達したときはキーワードだけ（前と同じ）。
- 効き具合は管理画面の「状態」の AI の欄（キャッシュから読めた量）で見られる（だれでも読める `/api/v1/info` からは外した。要件#114）。0 のままなら、指示文が毎回変わってしまっている（日時などを指示文に入れないこと）。

### 9.2 AI の API の登録・優先順位（要件#115）・Claude 以外のAI
- 管理画面の「AIのAPI」で、**1人用と対戦それぞれに**最大5個を優先順位つきで登録する（要件#116。対戦は「1人用と同じ並びを使う」も選べ、「1人用の並びを対戦に写す」でキーごと写せる。対戦の判定・客役の判定・不適切な発言のチェック・対戦のお客さんづくりは対戦の並び、それ以外は1人用の並び）。種類は Claude（Anthropic）・OpenAI・Gemini（Google）・DeepSeek・そのほか（OpenAI 互換。Ollama など）。同じ会社を2つ以上入れてもよい。モデルは候補から選ぶか手で入れる。キーは `var/secrets.json`（0600）にだけ保存し、画面にも記録にも全部は出さない。
- 使い方: 1位から順に呼び、**どんな失敗でも**（キーが無効・残高不足・利用制限・混雑・サーバーのエラー・時間切れ・答えの形が違う）次の順位へ。全体で 25 秒まで（ゲームは 35 秒で待つのをやめる）、残りが 3 秒を切ったら試さない。全部だめなら、今までどおりキーワード判定・台本に切り替わる。
- 登録ごとに: **お客さんづくりのモデル**（空なら同じモデル。お客さんづくりは1人につき1回なので、ここだけ賢いモデルにできる）、**1日の上限**（0 = なし。超えたらその日は次の順位へ。失敗には数えない。数はサーバーの日付〔UTC〕で数え、再起動で0に戻る）、**メモ**（管理画面にだけ出す）。
- **Claude だけ: 送る量が多いときのモデル**（要件#117）。登録ごとに「切り替えの目安（入力トークン。既定 90000）」と「切り替え先のモデル（既定 claude-sonnet-5-5。空なら切り替えない）」を決める。呼ぶ前に文字数で見積もり（日本語は1文字1トークン前後なので多めの見積もり）、目安の半分に届かなければ数えずにそのまま。届きそうなときだけ count_tokens で数え、目安を超えていたら切り替え先のモデルで呼ぶ（数えられなかったら文字数の見積もりで決める）。ふだんのゲームの呼び出しは数千トークンなので、ほとんど数えない（待ち時間が増えない）。切り替えたときはサーバーのログに出す。
- 失敗した API はしばらく飛ばす: 連続10回目の失敗までは5分、そこからは1回ごとに5分ずつ延ばして最大60分。成功したら回数は0に戻る。登録を保存し直した（種類・モデル・場所・キーを変えた）ときと、「この API を試す」でつながったときも0に戻る。AI が発言の内容のせいで答えを控えたときは、API の調子が悪いのではないので数えない（次の順位では試す）。
- 状態を調べるために AI を呼ぶことはない（遊んだときの呼び出しの成功・失敗だけを数える。紹介サイトの「サーバーの状況」も同じ）。
- 呼び方: Claude は公式 SDK（指示文・会話のキャッシュつき）。OpenAI・Gemini・DeepSeek・そのほかは Chat Completions（`/chat/completions`）。OpenAI `https://api.openai.com/v1`（`max_completion_tokens`）、Gemini `https://generativelanguage.googleapis.com/v1beta/openai`、DeepSeek `https://api.deepseek.com`（スキーマ指定に対応していないので `json_object` で、形は指示文で伝える）。そのほかは場所と JSON の出させ方を登録ごとに選ぶ。
- 管理画面でまだ保存していないときは、環境変数から登録を作る（`LLM_PROVIDER=openai_compatible` の API → `ANTHROPIC_API_KEY` → `OPENAI_API_KEY` → `GEMINI_API_KEY` → `DEEPSEEK_API_KEY` の順）。前の版で管理画面から入れた Claude・互換 API の設定とキーも、ここで使われる。一度保存すると、管理画面の登録だけを使う。
- 出力は JSON にさせ、サーバーで形を確かめる。
- OpenAI・Gemini・DeepSeek は、同じ前半の指示文を自動でキャッシュする（設定不要）。読めた量は管理画面の「状態」に出る。
- 料金の目安: 管理画面の「AIの料金」は、設定の「AIの料金表」にあるモデルだけを数える。OpenAI・Gemini・DeepSeek のモデルを使うなら、各社の料金ページの値を料金表に足すこと（無いモデルは 0 で数える）。
- 品質の注意: 判定の指示文は Claude に合わせて作っている。ほかのAIでは、判定が甘い・厳しい、言語の指定を守らない、などが起きうる。切り替えたら、数人分遊んで確かめること。
- テスト: `server/test/openai_compatible.test.ts`・`server/test/ai_fallback.test.ts`（偽の API サーバーで、切り替えと飛ばし方を確かめる）。

### 9.3 EOS に任せられること・任せないこと
| 項目 | 今 | EOS に移すと | 判断 |
|---|---|---|---|
| AIの判定・お客さんづくり | サーバー | 移せない（APIキーを配れない） | サーバーのまま。料金はキャッシュと上限で下げる |
| マッチング・フレンド招待 | EOS（あれば）→ 無ければサーバー | 済み（要件#48） | ― |
| 称号・実績 | ゲーム（このPC）に保存 | EOS の実績（Achievements）にも記録できる | EOS が使えるときは EOS の実績にも記録する（要件#78。称号の一覧が決まってから、開発者ポータルに同じIDで登録する） |
| レーティング・ランキング | サーバー（SQLite） | EOS の統計はゲームから書き込むので、改造で書き換えられる | 不正対策のためサーバーのまま。ランキングを出すのは小さな問い合わせ1つで、サーバー代はほぼかからない |
| 対戦の声 | サーバーが相手に中継し、文字起こしもする | EOS のボイスチャット（RTC）で相手に直接届けられる | 判定のための文字起こしにサーバーへの送信は残るので、減るのは中継の通信量だけ（1回 最大約0.4MB）。実機で確かめられる環境ができてから検討 |

## 10. 通報と不適切な発言（要件#87, #88）
- プレイヤーの通報と、自動で見つけた不適切な発言は `reports` テーブルに入る（reporter_id が `system:moderation` のものが自動）。
- 確かめ方の例（サーバーの中で）:
  ```bash
  sqlite3 server/var/cushara.db "SELECT datetime(created_at/1000,'unixepoch'), reporter_id, target_id, reason, note FROM reports ORDER BY id DESC LIMIT 50;"
  ```
- 不適切な発言の検出は、キーワード（`server/src/moderation.ts`）と、AI が使えるときは AI。AI は採点と同じ呼び出しで `flag` を返す（要件#93）。採点のない客役の最初のクレームだけ `moderateWithLlm` を別に呼ぶ（1人1分に30回まで）。
- 語の一覧は `data/moderation_words.json`（ゲームの `scripts/moderation.gd` と共通。要件#94）。ある程度の暴言（バカ・クソ店員 など）は止めず、性的な内容・差別・命を脅かす言葉・個人情報だけを止める。
- 名前（要件#94）: `POST /api/v1/me` の名前に不適切な言葉があれば 400 `name_not_allowed`。`POST /api/v1/guest` は既定の名前（名無しのスタッフ）にして作る。
- テスト: `server/test/anthropic_cache.test.ts`（偽の API サーバーで、キャッシュの印の位置と `flag` を確かめる）。


## 11. 管理画面（要件#100）
ブラウザで、サーバーの状態・通報・プレイヤー・対戦・AIの料金の目安・お知らせとメンテナンス・設定（APIキー・AIモデル・LLMの種類・上限・対戦の時間など、サーバーでする設定ぜんぶ）・操作の記録を見て変える。見た目より使いやすさ優先（設定は探す・Enter で保存・まとめて保存）。日本語だけ。

### 開き方
- サーバーが `127.0.0.1:8790`（`ADMIN_PORT`。0 で使わない）でだけ待ち受ける。家の PC からは SSH のトンネルで開く（docs/HOME_SERVER.md 5節、`deploy/windows/admin_tunnel.bat`）。
- 最初のパスワードは `server/var/admin_initial_password.txt`（環境変数 `ADMIN_PASSWORD` があればそれ）。ログイン後に変える。忘れたら `server/var/admin_auth.json` を消して再起動。

### 外からつながらないための決まり（`server/src/admin.ts`）
1. 待ち受けは 127.0.0.1 に固定（設定でも変えられない）。
2. 接続の相手が 127.0.0.1 / ::1 でなければ断る。
3. プロキシを通った印（CF-Connecting-IP・X-Forwarded-For・Forwarded など）があれば断る（Cloudflare Tunnel をまちがえて向けても入れない）。
4. Host が localhost / 127.0.0.1 でなければ断る（DNS リバインディング対策）。
5. パスワード（scrypt でハッシュにして保存）→ HttpOnly・SameSite=Strict の Cookie。変更の操作は CSRF の印と Origin も確かめる。ログインの失敗は15分に10回まで。
6. 画面に出すプレイヤーの名前・通報のメモ・会話は、すべて文字として入れる（HTML として解釈しない）。スクリプトは別のファイルで、CSP でインラインのスクリプトを禁止。

### できること
| 画面 | 内容 |
|---|---|
| 状態 | つながっている人・対戦中・待ち・部屋・プレイヤー数・今日の対戦・未対応の通報・利用停止中の数・AI と文字起こしの状態・メモリ・DB の大きさ・負荷。AIの接続の確認、サーバーの再起動（systemd が起動し直す） |
| 通報 | 未対応／対応済み／問題なし。会話（通報された試合だけ）を見る。相手の画面へ |
| プレイヤー | 名前・ID で探す。レート・勝敗・通報の履歴・最近の対戦・操作の記録。対戦だけ／全部の利用停止（24時間〜30日）、永久の利用停止（BAN）と解除、名前のリセット、称号をはずす、警告を送る（次にゲームを開いたときに出る） |
| 対戦 | 最近の100試合。会話は通報された試合だけ |
| AIの料金 | 日ごと・モデルごとの呼び出し・トークン・料金の目安、今月と月末の見込み、上限の目安を超えそうなら警告 |
| お知らせ・メンテナンス | タイトル画面に出すお知らせ（日・英・中）。メンテナンス中は対戦（マッチング・部屋）を止める（1人用は遊べる） |
| 設定 | `server/src/settings.ts` の一覧。DB（settings 表）に保存して、環境変数より優先。APIキーは `server/var/secrets.json`（持ち主だけ読める）に保存し、画面には最初と最後の数文字だけ |
| 操作の記録 | すべての操作。設定の変更は「前に戻す」（APIキーは戻せない。入れ直す） |
| AIの指示文（要件#130） | AI に渡す指示文（お客さんづくり・採点・客役の採点・不適切な発言のチェック・翻訳）を見て書きかえる。モード「プログラムの指示文」（既定）／「管理画面の指示文」（書いた欄だけ使い、空の欄はプログラムのまま）。答えの形（JSON）はプログラムが決めるので、指示文を変えても形はくずれない |
| バックアップ（要件#131） | 自動で取る・取らない、間隔（時間）、残す数（設定 → バックアップ）。今すぐ取る、一覧、消す。「全部を戻す」は ID を入力して確かめ、サーバーを再起動して入れかえる（入れかえる前の今のデータも写しておく）。「プレイヤーを戻す」は、そのバックアップの中から探して、その人だけ（名前・レート・勝敗・称号・名札・見た目・利用停止など）を戻す（つながっていれば切る）。置き場所は `server/var/backups/`（DB・secrets.json・お知らせの画像。フォルダは持ち主だけ読める。管理画面のパスワードは入れず、全部を戻しても今のパスワードのまま） |
| 対戦サーバー（要件#132） | 設定 → 対戦サーバー で、日本語・英語・中国語・韓国語・グローバルのサーバーごとに使う／休む。休んでいるサーバーはゲームで「休止中」と出て選べない（並んでいた人には `server_closed`）。グローバルは既定で休み（`VS_GLOBAL=1` で最初から開く）。翻訳のモデルは「AIのAPI」の登録ごとの「翻訳のモデル」（空なら採点のモデル） |

### 利用停止・警告のゲームでの見え方
- 全部の利用停止: ログイン（`/api/v1/me` など）が 403 `banned`、WebSocket も断る。止めた瞬間につながっていた接続も切る。ゲームは「このアカウントは利用停止中です」と理由を出し、1人用（台本）だけ遊べる。
- 対戦の利用停止・メンテナンス: マッチング・部屋が `versus_banned` / `maintenance` で断られる。
- 警告: `/api/v1/me` の `warning` をタイトル画面で見せ、「わかりました」で `/api/v1/me/ack_warning`。
- お知らせ・メンテナンスは `/api/v1/info` の `notices`・`maintenance` で、タイトル画面の右下の付箋に出る。

### 会話の保存（プライバシーポリシーと同じ）
試合の会話（文字。声の文字起こしを含む。声そのものは保存しない）は、ふだんはメモリにだけ置き、試合の終わりから1時間で捨てる。通報（プレイヤーの通報・自動の不適切発言の検出）があった試合だけを DB（match_logs 表）に保存し、30日で消す（6時間ごとに確かめる）。管理画面で会話を見ると、その操作も記録に残る。

## 12. 対戦サーバーとグローバルの翻訳（要件#132）

- 1台のゲームサーバーの中で、言語ごと（ja/en/zh/ko）とグローバルの「サーバー」に分ける。マッチングは同じサーバーの人どうしだけ。
- 言語のサーバー: 判定・お客さんの設定はそのサーバーの言語。
- グローバル: 言語をまたいで組む。判定・お客さんの設定は英語。翻訳モードの人には、相手のセリフ・採点のコメント・お客さんの設定を自分の言語に訳して、あとから送る（`line_tr` など）。試合は訳を待たない。
- 訳は対戦の AI の並びで呼ぶ（用途 translate。登録ごとの「翻訳のモデル」、空ならそのモデル）。同じ文は 2000 件まで覚えておき、もう一度呼ばない。
- 判定は原文で行う（訳したものでは採点しない）。
- 公開の `/api/v1/info` の `versus_servers` に、サーバーごとの開いている・休みだけを出す。
