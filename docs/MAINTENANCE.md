# 保守・運用・配布の資料

## 1. 開発環境

1. Godot 4.5（標準版。.NET版ではない）を https://godotengine.org からダウンロード。
2. Godot を起動し「インポート」でこのフォルダの `project.godot` を選ぶ。
3. F5 で実行。

コマンドラインでの確認:

```bash
godot --headless --import
```

```bash
godot --headless -- --smoke
```

`SMOKE OK` が出れば、台本モードで全ステージを最後まで通せている。

対戦の自動テスト（2つの端末で同時に実行する）:

```bash
godot --headless -- --smoke-host
```

```bash
godot --headless -- --smoke-join
```

画面の確認用スクリーンショット（`docs/screenshots/` に保存される）:

```bash
godot -- --shots
```

CIに撮らせたいときは、コミットメッセージに `[shots]` を入れてプッシュする。

## 2. Windows 用 exe の作り方

- 自動: GitHub に push すると `.github/workflows/build.yml` が動き、成果物 `CusHara-windows`（`CusHara.exe`）が Actions の画面からダウンロードできる。
- 手動: Godot の「プロジェクト → エクスポート」で「Windows Desktop」を選ぶ（初回はエクスポートテンプレートのダウンロードが必要）。

```bash
godot --headless --export-release "Windows Desktop" build/windows/CusHara.exe
```

exe にデータ（pck）を埋め込む設定なので、配るのは exe 1つでよい。

## 3. よくある変更

| やりたいこと | 触る場所 |
|---|---|
| 台本のお客さんを増やす・直す | `scripts/scenarios.gd`（形は SPEC 4節。キーを1つでも欠くと既定のセリフになる） |
| 難易度（怒りの上がる速さ） | `solo_game.gd` の `BASE_ANGER_RATE` / `RATE_STEP`、各お客さんの `patience` |
| 得点・ランクの境目 | `solo_game.gd` の `SCORE_*`、`main.gd` の `RANKS` |
| キーワード採点の語や点 | `offline_judge.gd` の先頭の配列と `judge()` |
| 定型文ボタン | `hud.gd` の `DEFAULT_PHRASES` |
| AIの人格・採点基準 | `llm_client.gd` の `GM_SYSTEM` / `GEN_SYSTEM` / `PERSONALITIES` |
| 使えるAIモデルの一覧・既定 | `game_settings.gd` の `MODELS` と `model` の初期値 |
| ゲームセンターの台の配置・色・景品 | `arcade_stage.gd` の `_build_cranes()` / `PALETTE` / `_fill_prizes()` |
| 対戦の制限時間・往復数・怒りの速さ | `versus_game.gd` の先頭の定数 |
| レーティングのK値・ランク名 | `game_settings.gd` の `RATING_K` / `VERSUS_RANKS` |
| 客役の定型文・客役セリフの評価 | `versus_game.gd` の `CUSTOMER_PHRASES`、`offline_judge.gd` の `judge_customer_line` |
| ステージを増やす | `main.gd` の `STAGES` と `STAGE_ORDER`、`scenarios.gd`、`llm_client.gd` の `STAGE_TEXT`、`stage_world.gd` の `build()` |

GDScript を書くときの決まり（このプロジェクトで事故を避けるため）:
- 辞書から取り出した値は `:=` で受けない。`var x: float = float(d.get("k", 1.0))` のように型を書く。
- Node3D のスクリプトで `name` `position` `scale` `rotation` を変数名・引数名に使わない。
- `await` を足したら中断チェックを入れる（DESIGN 5節）。

## 4. Claude API が変わったとき

- モデルIDの廃止・追加 → `game_settings.gd` の `MODELS`。
- APIバージョン → `llm_client.gd` の `API_VERSION`。
- フォールバックのベータ名 → `FALLBACK_BETA`。不要になれば `_supports_fallback()` が常に false を返すようにすれば送らなくなる。
- 設定画面の「接続テスト」で疎通を確認できる。

## 5. 困ったとき

| 症状 | 見るところ |
|---|---|
| 文字が□になる | `assets/fonts/` の ttf があるか、`project.godot` の `gui/theme/custom_font` |
| 起動直後にエラー | `stage_world.gd` / `customer_character.gd` があるか（HANDOVER参照）。`godot --headless --import` のログ |
| AIモードにならない | 設定でキーが入っているか、「AIお客さんを使う」がONか、接続テストの表示 |
| お客さんが来ないまま止まる | `customer_character.gd` が `arrived` を必ず発行しているか |
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

### 対戦のSteam招待・マッチングを有効にする（未実施）
ゲーム側のコード（`net_session.gd`）は書いてあるが、GodotSteam 本体は入れていない。入れないと、ロビー画面のSteamボタンは押せないままになる。

1. GodotSteam の GDExtension 版（Godot 4.5 用）を公式サイトから入手し、`addons/godotsteam/` に置く。
2. 開発中は、プロジェクトのフォルダに `steam_appid.txt`（アプリIDだけを書いたファイル）を置く。配布物には入れない。
3. Steam を起動した状態でゲームを起動し、ロビー画面でSteamボタンが押せることを確認する。
4. フレンド招待とランダムマッチを2台で試す。うまくいかないときは `net_session.gd` の `_on_lobby_created` / `_on_lobby_joined` を、入れた GodotSteam のドキュメントと見比べる（関数名がバージョンで違う可能性がある）。

作業環境からは GodotSteam の公式サイトに接続できず、関数名を確認できなかった。ここは必ず実機で確かめること。

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
- マニフェストは `runFullTrust`（通常のデスクトップアプリ）と `internetClient` / `internetClientServer`（AI通信と対戦）を宣言している。`runFullTrust` はストア提出時に利用理由の入力を求められる。
- ストアの説明とプライバシーポリシーに、APIキーをユーザーが入力すること、外部サービス（Anthropic）と通信することを書く必要がある。
- MSIX を実際にインストールして起動する確認は、まだ誰も行っていない。

## 8. ライセンス

- Noto Sans JP: SIL Open Font License 1.1（`assets/fonts/OFL.txt`。配布物に同梱すること）。
- Godot Engine: MIT。配布物にライセンス表記が必要（Godotの公式ドキュメント「Complying with licenses」参照）。**まだゲーム内に表記していない。**
