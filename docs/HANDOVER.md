# 引き継ぎ書（2026-11-17 時点）

次に作業する人（依頼者本人、または Opus など）が、ここだけ読めば続きを始められるようにまとめる。
読む順: この文書 → [REQUIREMENTS_LOG.md](REQUIREMENTS_LOG.md) → [SPEC.md](SPEC.md) → [DESIGN.md](DESIGN.md) → [MAINTENANCE.md](MAINTENANCE.md)。

## 1. いちばん大事なこと: このコードは一度も実行されていない

作業環境では Godot の実行が許可されず、**コンパイルも起動も確認できていない**。確認の手段は GitHub Actions（`.github/workflows/build.yml`）だけで、その結果もまだ見ていない。
GDScript の文法エラーや API 名の間違いが残っている前提で、最初に次を行うこと。

1. GitHub の Actions タブで最新の「Build」を開き、「Import project」と「Smoke test」のログを読む。
2. `SCRIPT ERROR` / `Parse Error` の行に、ファイル名と行番号が出る。上から順に直す。
3. `SMOKE OK` が出て、成果物 `CusHara-windows` ができたら、exe を Windows で起動して目で確認する。

手元に Godot 4.5 があれば、`godot --headless --import` と `godot --headless -- --smoke` で同じことができる。

## 2. 何がどこまでできているか

| 部分 | 作成者 | 状態 |
|---|---|---|
| プロジェクト設定、Windows出力設定、CI | Fable | 作成済み・未実行 |
| 1人用の進行（`solo_game.gd`） | Fable | 作成済み・未実行 |
| 画面（`main.gd`、`hud.gd`、`ui_kit.gd`） | Fable | 作成済み・未実行。レイアウトは目で見ての調整が必要 |
| Claude API 連携（`llm_client.gd`） | Fable | 作成済み・**実通信は未確認** |
| キーワード採点（`offline_judge.gd`） | Fable | 作成済み・未実行 |
| 効果音（`sfx.gd`）、設定保存（`game_settings.gd`） | Fable | 作成済み・未実行 |
| ゲームセンター3D（`arcade_stage.gd`、クレーンゲーム15台） | Fable | 作成済み・**見た目は未確認** |
| 台本データ（`scenarios.gd`、コンビニ8人・ゲームセンター7人） | Sonnet（下書き） | 括弧の対応と全キーの有無だけ機械的に確認済み。作成者は「各8人」と報告したが実際のゲームセンターは7人。**内容のFableレビューは未実施** |
| コンビニ3D・ステージ切替（`stage_world.gd`） | Opus（下書き） | ファイルは届いた。**Fableのレビュー未実施** |
| お客さん3Dキャラ（`customer_character.gd`） | Opus（下書き） | ファイルは届いた。**Fableのレビュー未実施** |
| 対戦モード・レーティング | ― | **未着手**（仕様案は SPEC 6節） |
| Steam 用の配布設定（vdf、GodotSteam） | ― | **未着手**（手順は MAINTENANCE 6節） |
| Microsoft Store 用の MSIX | ― | **未着手**（手順は MAINTENANCE 7節） |
| 仕様書・設計書・保守資料 | Fable | 初版 |

## 3. 残作業（優先順）

1. **CIを緑にする**（1節）。3D側の約束は DESIGN 4節。
2. **サブエージェント下書きのレビュー**（要件#10「品質に関わる部分はFable」）:
   - `scenarios.gd`: 文法（括弧・カンマ・キーの欠け）、セリフの面白さ、`solution_keywords` が `memo` の正解と合っているか。「景品交換」という語は全スクリプトに無いことを確認済み（要件#11）。ゲームセンターは7人なので1人以上の追加が望ましい。
   - `stage_world.gd`: `arcade` のとき `arcade_stage.gd` に任せているか（自前のゲームセンターを作っていないか）。カメラから見た構図。
   - `customer_character.gd`: 顔が2m先から読めるか、怒りの段階表現、`arrived` / `left` が必ず発行されるか。
3. **実機での見た目・手触りの調整**: 文字サイズ、パネルの重なり、怒りの上昇速度（日本語入力の時間に対して速すぎないか）、クレーンゲームの見栄え。
4. **AIモードの実通信確認**: 設定画面でキーを入れ「接続テスト」→ 1シフト遊ぶ。`fallbacks` や `output_config` で400が出ないかを見る。
5. **対戦モード**（要件#12, #15, #16）: `versus_game.gd` と通信層を新規作成。まずIP直結で動かし、CIで2プロセスの自動対戦を通してから GodotSteam を足すのが安全。GodotSteam の API はバージョン差があるので公式ドキュメントで確認すること。
6. **Steam / Microsoft Store 用の成果物**（要件#8）。どちらも依頼者のアカウント登録とIDが先に必要。
7. **仕上げ**: BGM、Godotのライセンス表記、APIキーの暗号化保存、タイトルの「対戦 ― 準備中」ボタンの有効化。

## 4. 依頼者に確認が必要なこと

- 要件#11 の解釈（景品交換カウンターも、景品交換を題材にしたクレームも無くす）で合っているか。
- 対戦のレーティングをPC内保存でよいか（改ざん可能）。Steamリーダーボードまで要るか。
- AIの既定モデル。現在は `claude-opus-5-5`。反応速度と料金を優先するなら Haiku 5.5 が向くが、既定は変えていない。
- ゲーム名「カスハラ防衛線」、店名「ハッピーマート」「ゲームパラダイス」は仮の案。

## 5. 作業の進め方の決まり

- 依頼者の指示は、受けたらすぐ REQUIREMENTS_LOG.md に追記する（要件#13）。
- ブランチは `claude/wizardly-keller-c3rj2v`。リポジトリにはこのブランチしか無い（マージ先が無いためプルリクエストは作っていない）。
- 仕様を変えたら SPEC.md、作りを変えたら DESIGN.md を同じコミットで直す。
