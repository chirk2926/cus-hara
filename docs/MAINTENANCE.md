# 保守・運用・配布の資料

## 1. 開発環境

1. Godot 4.5（標準版。.NET版ではない）を https://godotengine.org からダウンロード。
2. Godot を起動し「インポート」でこのフォルダの `project.godot` を選ぶ。
3. F5 で実行。

サーバーも手元で動かす（AIキーなしでもキーワード判定で遊べる）:

```bash
cd server && npm ci && npm start
```

ゲームの設定画面「サーバーのURL」は既定で `http://127.0.0.1:8787`。

コマンドラインでの確認（1人用を全ステージ自動プレイ。`SMOKE OK` が出れば成功）:

```bash
godot --headless --import
```

```bash
godot --headless -- --smoke --source=offline
```

```bash
godot --headless -- --smoke --source=server --server=http://127.0.0.1:8787
```

対戦の自動テスト（2つの端末で同時に実行する。ランクマッチで組まれて最後まで戦う）:

```bash
godot --headless -- --vs-smoke=text --profile=A --server=http://127.0.0.1:8787
```

```bash
godot --headless -- --vs-smoke=text --profile=B --server=http://127.0.0.1:8787
```

音声の対戦の自動テストは、サーバーを `STT_PROVIDER=mock` で起動し、`--vs-smoke=voice` にする。

画面の確認用スクリーンショット（`docs/screenshots/` に保存される。`--lang=en` で英語）:

```bash
godot -- --shots --lang=ja
```

CIに撮らせたいときは、コミットメッセージに `[shots]` を入れてプッシュする。

## 2. Windows 用 exe の作り方

- 自動: GitHub に push すると `.github/workflows/build.yml` が動き、成果物 `CusHara-windows`（`CusHara.exe`）が Actions の画面からダウンロードできる。
- 手動: Godot の「プロジェクト → エクスポート」で「Windows Desktop」を選ぶ（初回はエクスポートテンプレートのダウンロードが必要）。

```bash
godot --headless --export-release "Windows Desktop" build/windows/CusHara.exe
```

exe にデータ（pck）を埋め込む設定なので、配るのは exe 1つでよい。

### 2.1 コードのロック（暗号化。要件#94）
- CI が配る exe は、中のスクリプトと素材を AES-256 で暗号化してある。読めるのは同じ鍵を組み込んだ書き出し用のひな形だけなので、CI の `enc_template` ジョブが Godot のソースからひな形を作る（初回 30 分ほど。2回目からはキャッシュ）。
- **鍵の登録（おすすめ）**: GitHub のリポジトリの Settings → Secrets and variables → Actions に `GODOT_SCRIPT_ENCRYPTION_KEY` を登録する（64けたの16進数。例: `openssl rand -hex 32` で作る）。鍵はチャットやファイルに書かない。登録しないときは、CI が初回に鍵を作って Actions のキャッシュに入れて使う（キャッシュが消えると、次の版は別の鍵になる。それでも動くが、鍵を自分で持っておきたいなら登録する）。
- 鍵を変えると、ひな形を作り直すので、その回の CI は 30 分ほど長くなる。
- 手で書き出すときは暗号化されない（スクリプトは圧縮したトークンにはなる）。暗号化した exe が欲しいときは CI の成果物を使う。
- 限界: 鍵は exe の中にあるので、専門の道具と時間をかければ取り出せる。大事な判定・API キーはサーバーにあるので、exe を解析されても不正には使えないようにしてある。

## 3. よくある変更

| やりたいこと | 触る場所 |
|---|---|
| 台本のお客さんを増やす・直す | `data/scenarios.json` と `data/scenarios.en.json`・`.zh.json`・`.ko.json`（同じ順番で全部。形は SPEC 4節） |
| 1人用の難易度（怒りの上がる速さ） | `solo_game.gd` の `BASE_ANGER_RATE` / `RATE_STEP`、各お客さんの `patience` |
| ゲームセンターの台ごとのボタン | `data/actions.json` の `machines`（ボタン）・`labels`（表示名）・`default`（効果）。お客さんの `machine` と `actions` |
| ペイアウト率の効き方（クレームの出やすさ・言う金額） | `server/src/scenarios.ts` の `spendWeight` / `materializeSpend` と、同じ決まりの `scripts/scenarios.gd`（両方そろえて直す） |
| 確率設定の取れやすさ・テストプレイの回数 | `scripts/crane_minigame.gd` の `_win_chance` / `TEST_PLAYS` |
| 売上・店舗レビューと点数のボーナス | `scripts/solo_game.gd` の `SALES_*` / `REVIEW_*` / `_finish_summary` |
| 言語ごとのお金の単位・換算 | `scripts/game_settings.gd` の `CURRENCY` と `server/src/lang.ts` の `money`（両方そろえる） |
| 言語を増やす | `game_settings.gd` の `LANGS`、`data/i18n/<lang>.json`、`data/scenarios.<lang>.json`、`judge_words.json`・`actions.json` の <lang>、`server/src/lang.ts` の `LANGS`、`tools/i18n.py` の `LANGS`。字体に無い文字は `ui_kit.gd` の予備の字体で補う |
| チュートリアルの説明文・順番 | `scripts/tutorial.gd` の `_go`（文は `data/i18n/en.json` にも英訳を足す） |
| 1人用の得点・ランクの境目 | `solo_game.gd` の `SCORE_*`、`main.gd` の `RANKS` |
| キーワード判定の語 | `data/judge_words.json`（サーバーとクライアント共通） |
| キーワード判定の点数 | `server/src/keyword_judge.ts` と `scripts/offline_judge.gd`（両方を同じに） |
| 接客用語のタグ | `hud.gd` の `DEFAULT_PHRASES`（英訳を `en.json` に） |
| AIの人格・採点基準 | サーバー: `server/src/llm.ts` の `GEN_SYSTEM` / `GM_SYSTEM` / `VS_CUSTOMER_SYSTEM` / `PERSONALITIES`。自分のキー用: `llm_client.gd` |
| サーバーのAIモデル | 環境変数 `CLAUDE_MODEL` |
| 対戦の秒数・往復数・怒りの速さ | `server/src/config.ts` の `versus` |
| マッチングの範囲の広がり方 | `server/src/config.ts` の `match` |
| レーティングのK値・ランク名 | `server/src/rating.ts`（ランク名の英訳を `en.json` に） |
| 客役の接客用語（言い返し） | `versus_game.gd` の `CUSTOMER_PHRASES` |
| ゲームセンターの台の配置・色・景品 | `arcade_stage.gd` の `_build_cranes()` / `PALETTE` / `_fill_prizes()` |
| 画面の色・書体・形 | `ui_kit.gd`（決まりは UI_GUIDE.md） |
| ステージを増やす | `main.gd` の `STAGES` と `STAGE_ORDER`、台本、`server/src/scenarios.ts` の `STAGES`、`llm.ts` の `STAGE_TEXT`、`stage_world.gd` の `build()` |

GDScript を書くときの決まり（このプロジェクトで事故を避けるため）:
- 辞書から取り出した値は `:=` で受けない。`var x: float = float(d.get("k", 1.0))` のように型を書く。
- Node3D のスクリプトで `name` `position` `scale` `rotation` を変数名・引数名に使わない。
- `await` を足したら中断チェックを入れる（DESIGN 5節）。
- 画面に出す文は `tr("日本語")` で書き、英訳を足す（9節）。

## 4. Claude API が変わったとき

- サーバー: `server/package.json` の `@anthropic-ai/sdk` を上げ、`npm test` と `npm run typecheck`。モデルは `CLAUDE_MODEL`。
- 自分のキー用（クライアント）: モデル一覧は `game_settings.gd` の `MODELS`、APIバージョンは `llm_client.gd` の `API_VERSION`、フォールバックのベータ名は `FALLBACK_BETA`。
- 設定画面の「接続を確かめる」で疎通を確認できる。

## 5. 困ったとき

| 症状 | 見るところ |
|---|---|
| 文字が□になる | `assets/fonts/` の ttf があるか、`project.godot` の `gui/theme/custom_font` |
| 起動直後にエラー | `godot --headless --import` のログ |
| タイトルに「サーバーにつながりません」 | 設定の「サーバーのURL」、サーバーが動いているか（`curl <URL>/healthz`） |
| 1人用でAIのお客さんにならない | サーバーの起動ログの「AI判定: ON/OFF」、`ANTHROPIC_API_KEY`、`LLM_PER_MINUTE` の上限 |
| 対戦で相手が見つからない | 相手と言語・形式（文字/音声）がそろっているか。ロビーの「待っている人」の数 |
| 音声対戦が選べない | サーバーの `STT_PROVIDER`（`none` だと選べない） |
| 声が届かない／文字にならない | Windows のマイクの許可、`project.godot` の `audio/driver/enable_input`、文字起こしサーバーのログ |
| 英語に訳されていない文がある | `python3 tools/i18n.py check` |
| CIの出力ステップで失敗 | テンプレートのバージョン（`GODOT_RELEASE`）と `export_presets.cfg` の preset 名 |

## 6. Steam で配布する

前提: Steamworks への登録（登録料が必要）とアプリIDの取得。これは依頼者本人の作業。

用意してあるもの: `packaging/steam/app_build.vdf`（アップロード定義のひな形）と `packaging/steam/README.md`（手順）。

1. CI の成果物 `CusHara-windows`（`CusHara.exe`）を `packaging/steam/content/` に置く。
2. `app_build.vdf` のアプリIDとデポIDを自分のものに書き換える。
3. Steamworks SDK の `steamcmd` でアップロードし、管理画面でビルドをブランチに設定する。

```bash
steamcmd +login <アカウント名> +run_app_build <app_build.vdf の絶対パス> +quit
```

### 対戦とSteamの関係
対戦（ランクマッチ・フレンド対戦）は自前のゲームサーバー経由なので、Steam の機能は使わない（Microsoft Store 版とも対戦できる）。
フレンド対戦は部屋コードを伝えて遊ぶ。Steam のフレンド招待から部屋コードを渡す機能は、GodotSteam を入れれば足せる（未実施。要件#15 は #19 で置き換え）。

## 7. Microsoft Store で配布する

前提: Microsoft パートナーセンターの開発者登録と、アプリ名の予約。これも依頼者本人の作業。

用意してあるもの: `packaging/msix/AppxManifest.xml`（ひな形）、`packaging/msix/Assets/`（ロゴ）、`packaging/store_icon_1024.png`（ストア掲載用アイコン）、CIの `msix` ジョブ。

1. パートナーセンターの「製品 ID」ページで、パッケージ名（Identity Name）・発行者（Publisher、`CN=...`）・発行者表示名を控える。
2. GitHub のリポジトリの Settings → Secrets and variables → Actions → Variables に登録する:
   `MSIX_IDENTITY_NAME` / `MSIX_PUBLISHER` / `MSIX_PUBLISHER_DISPLAY` / `MSIX_VERSION`（例 `1.0.0.0`。4つの数字）。
   未登録のときは仮の値（`CusHara.Dev` / `CN=CusHaraDev`）で作られる。**仮の値のままではストアに提出できない。**
3. プッシュすると CI が `CusHara-msix`（`CusHara.msix`）を成果物として作る。
4. パートナーセンターに MSIX をアップロードして審査に出す。ストア提出用は署名不要（ストアが署名する）。手元で試すときだけ、自己署名証明書で `signtool` 署名し、証明書を信頼済みに入れる必要がある。

注意:
- マニフェストは `runFullTrust`（通常のデスクトップアプリ）、`internetClient`（サーバーとの通信。要件#108 で使っていない `internetClientServer` を外した）、`microphone`（音声対戦）を宣言している。`runFullTrust` はストア提出時に利用理由の入力を求められる。
- ストアの説明とプライバシーポリシーに、ゲームサーバーと通信すること（名前・対戦の記録・入力した文章・音声が送られ、AIの判定に使われること）、自分のAPIキーを入れた場合は Anthropic と直接通信することを書く必要がある。
- MSIX を実際にインストールして起動する確認は、まだ誰も行っていない。
- 掲載の文（3言語）・画像・年齢レーティング（IARC）の答えの案・提出前の確認の一覧は [STORE_LISTING.md](STORE_LISTING.md)。プライバシーポリシーの URL はゲームサーバーの `https://<ドメイン>/privacy`（`server/public/privacy.*.html` の〔運営者名〕〔連絡先メールアドレス〕を書きかえてから）。
- ストアの画像: コミットのメッセージに `[shots]` を入れてプッシュすると、CI が 1920×1080 で `docs/store/` に描く。
- 実績: EOS の開発者ポータルに t001〜t155 を登録する（docs/HANDOVER.md 4b）。
- コードのロックの鍵は GitHub の Secrets の `GODOT_SCRIPT_ENCRYPTION_KEY`（2.1節）。ストアに出す版は、鍵を Secrets に入れてから作る（自動で作られた鍵はキャッシュが消えると変わる）。

## 8. ゲームサーバーの運用

詳細は [SERVER.md](SERVER.md)。自宅の Linux サーバー（Cloudflare Tunnel・管理画面は SSH で）の手順は [HOME_SERVER.md](HOME_SERVER.md)。要点:
1. Linux のサーバーに Docker で `server/compose.yaml` を動かす（または Node.js 22.18 以上で `npm start`）。`ANTHROPIC_API_KEY` を環境変数で渡す。
2. 前に HTTPS 終端（Caddy / nginx）を置き、`https://` と `wss://` で公開する。
3. `scripts/game_settings.gd` の `DEFAULT_SERVER_URL` を本番のURLに書き換えてから、配布用の exe / MSIX を作る。
4. 音声対戦を使うなら、文字起こしサーバー（whisper.cpp の `whisper-server` など）を用意して `STT_PROVIDER` と `STT_URL` を設定する。
5. AIの料金は運営（キーの持ち主）にかかる。`LLM_PER_MINUTE` で1人あたりの回数を制限できる。Anthropic のコンソールで利用上限も設定しておく。
6. バックアップは `DB_PATH` のファイル（`-wal` も）。

## 9. 翻訳（多言語）

- 画面の文言を足したり変えたりしたら、次を実行して訳漏れを確認し、`data/i18n/en.json` に英訳を足す（CIでも検査される）。

```bash
python3 tools/i18n.py check
```

```bash
python3 tools/i18n.py missing en
```

- 台本は `data/scenarios.json`（日本語）と `data/scenarios.<言語>.json`（英語・中国語・韓国語）。**お客さんの順番と見た目の値をそろえる**こと（サーバーのテストが項目の有無を検査する）。
- 判定の語は `data/judge_words.json` の `ja` / `en`。店長の一言の文言は `server/src/keyword_judge.ts` と `scripts/offline_judge.gd` の `COMMENTS`。

### 言語を増やす
1. `data/i18n/<言語>.json` を作る（`python3 tools/i18n.py missing <言語>` で空の一覧が作れる）。`tools/i18n.py` の `LANGS` に足す。
2. `data/scenarios.<言語>.json` と `data/judge_words.json` の `<言語>` を作る。
3. サーバー: `server/src/lang.ts` の `LANGS`、`keyword_judge.ts` の `COMMENTS` と `OFFTOPIC`、`llm.ts` の `LANG_LINE` に足す。
4. クライアント: `game_settings.gd` の `LANGS`・`CURRENCY`、`offline_judge.gd` の `COMMENTS`・`OFFTOPIC`、`llm_client.gd` の言語指定に足す。言語ごとのセリフを持つ所（`age_check.gd` の `_tr`、`solo_game.gd` の `Judge.pick_lang`・`_smell_talk`・`_wants_other_id` など、`repair_stage.gd` の看板）にも足す。`grep -n '"zh"' scripts/*.gd server/src/*.ts` で探せる。
5. 言語ごとの項目を持つデータ（`data/titles.json`・`data/shop.json`・`data/actions.json`・`data/offenders.json`）にその言語を足す。
6. その言語の字がフォントに無ければ、`assets/fonts/` にフォントを置いて `ui_kit.gd` の予備に足す（韓国語は `F_KR`）。
7. プライバシーポリシー: `tools/privacy_gen.py` に足して `python3 tools/privacy_gen.py server/public`。サーバーの `/privacy` と、お知らせ（`db.ts` の `title_<言語>`・`text_<言語>`、`admin/app.js` の `LANGS`）にも足す。
（韓国語は要件#102 でこの手順で足した）

## 10. ライセンス（詳しくは ENGINE.md）

- フォント（Noto Sans JP、Yusei Magic、DotGothic16、Dela Gothic One）: すべて SIL Open Font License 1.1（`assets/fonts/licenses/`。配布物に同梱すること）。
- Godot Engine: MIT。有料販売してよい（ロイヤリティなし）。ライセンス表記はゲーム内の「ライセンス」画面で表示している。
- BGM: `tools/make_bgm.py` で作ったオリジナル。作り直すときは `python3 tools/make_bgm.py`（ffmpeg が必要）。
- サーバーの依存（@anthropic-ai/sdk、ws、zod）: MIT。
