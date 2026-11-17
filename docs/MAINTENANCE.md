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

## 6. Steam で配布する（未実施。手順の設計）

前提: Steamworks への登録（登録料が必要）とアプリIDの取得。これは依頼者本人の作業。

1. CI の成果物 `CusHara.exe` を `steam/content/` に置く。
2. Steamworks SDK の `steamcmd` 用に、アプリ定義（`app_build_<AppID>.vdf`）とデポ定義（`depot_build_<DepotID>.vdf`）を作る。`ContentRoot` を `steam/content`、`FileMapping` を `*` → `.` にする。
3. `steamcmd +login <アカウント> +run_app_build <vdfのパス> +quit` でアップロードし、Steamworks の管理画面でビルドをブランチに設定する。
4. 起動オプションは `CusHara.exe` を指定。
5. 対戦モード（Steam招待・マッチング）には GodotSteam（GDExtension）を `addons/` に入れる必要がある。入れたら `steam_appid.txt`（開発時のみ）も必要。**まだ入れていない。**

## 7. Microsoft Store で配布する（未実施。手順の設計）

前提: Microsoft パートナーセンターの開発者登録と、アプリ名の予約。これも依頼者本人の作業。

1. パートナーセンターで予約した「パッケージ名」「発行者ID（CN=...）」を控える。
2. `AppxManifest.xml` を作る（Identity の Name / Publisher / Version、`<Application Executable="CusHara.exe" EntryPoint="Windows.FullTrustApplication">`、Capability に `runFullTrust` と `internetClient`）。ロゴ画像（44×44、150×150、ストアロゴ50×50）が必要。
3. Windows SDK の `makeappx pack /d <フォルダ> /p CusHara.msix` で MSIX を作る（GitHub Actions の `windows-latest` で実行できる）。
4. ストア提出用は署名不要（ストアが署名する）。手元で試すときだけ `signtool` で自己署名する。
5. パートナーセンターに MSIX をアップロードして審査に出す。

注意: ストア版ではAPIキーをユーザーに入力させる点と、外部サービス（Anthropic）への通信があることをストアの説明とプライバシーポリシーに書く必要がある。

## 8. ライセンス

- Noto Sans JP: SIL Open Font License 1.1（`assets/fonts/OFL.txt`。配布物に同梱すること）。
- Godot Engine: MIT。配布物にライセンス表記が必要（Godotの公式ドキュメント「Complying with licenses」参照）。**まだゲーム内に表記していない。**
