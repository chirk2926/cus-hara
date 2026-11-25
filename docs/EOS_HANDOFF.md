# EOS の残りの作業（Chrome が使える環境で。要件#133）

このリポジトリでは、EOS を組み込む CI の準備まで済んでいる。残りは **ブラウザでの設定**なので、
Chrome（Claude in Chrome など）が使える環境で行う。

> **決まり（依頼者の指示）**
> - **EOS 系の操作は、するまえに依頼者に確認する**（1つずつ「これをします」と伝えてから）。
> - プッシュは EOS 系が終わってから。
> - 本物の値（Client Secret・暗号鍵）は、チャット・リポジトリ・ログに書かない。GitHub の Secrets に依頼者が自分で入れる。
> - Product ID・Sandbox ID・Deployment ID は依頼者から受け取り済み（秘密ではないが、リポジトリには書かず GitHub の Variables に入れる）。

## 今の状態

| もの | 状態 |
|---|---|
| ゲームの EOS のコード（`scripts/eos_matchmaker.gd`・ボイス・実績） | できている。プラグインと値が無いあいだは EOS なしで動く |
| Product ID / Sandbox ID / Deployment ID | 受け取り済み。**GitHub の Variables に入れた**（2026-11-25。EOSG_ZIP_URL・EOSG_ZIP_SHA256 も。リポジトリ chirk2926/cus-hara） |
| クライアントのポリシー・クライアント | **できている**（2026-11-25 に確認。ポリシー GameClient に Achievements・Lobbies・Stats・Voice など。クライアント「Customer Harassment Defense Line」）。Client ID・Secret を Secrets に入れるのは依頼者 |
| 暗号鍵・Client ID・Client Secret | **Secrets に入った**（2026-11-25。依頼者が入れた。名前は一覧で確認） |
| EOSG プラグイン | 版は **2.3.1**（Godot 4.5 対応。自動読み込みの名前も tools/eos_ci.py と同じ）。Variables に入れるのは下の 3. |
| 実績（t001〜t155） | ZIP はできている（`tools/eos/make_achievements_zip.ps1` → `tools/eos/out/achievements_import.zip`）。**インポート済み**（2026-11-25。155 個） |
| CI | できている（`.github/workflows/build.yml` の「EOS plugin」「EOS settings」、`tools/eos_ci.py`） |

## 手順

### 1. 開発者ポータル（https://dev.epicgames.com/portal）
1. 該当のプロダクトを開き、**Product Settings → Clients** で「クライアントのポリシー」を作る。
   - ポリシーの種類: `GameClient`（Lobbies・Connect・Achievements・RTC を許可）。
2. そのポリシーで **クライアント**を作り、Client ID を控える。Client Secret は **依頼者が自分で** GitHub の Secrets に貼る（チャットに出さない）。
3. **Identity Providers**: 今は「Epic アカウント → 無ければ端末 ID（Device ID）」でログインする。追加の設定はいらない。
4. **Epic Account Services**（フレンド招待を使う場合）: アプリ名・権限（基本プロフィール・フレンド・オンライン状態）を設定。Brand Review が要る。使わないならスキップしてよい（ランクマッチは Device ID で動く）。
5. **Achievements**: 称号と同じ ID で登録する。
   - ID: `t001`〜`t155`（名前・説明は `data/titles.json`。英語名は `data/i18n/en.json`）。
   - t151〜t155 はハードコアの称号。
   - 数が多いので、ポータルの一括登録（CSV のインポート）があればそれを使う。CSV は `data/titles.json` から作る（このとき Claude が作ってよい）。
6. Sandbox・Deployment が受け取った ID と同じものか（Live / Dev）を確かめる。

### 2. GitHub（リポジトリの Settings → Secrets and variables → Actions）
**Variables**（秘密ではない）:
| 名前 | 値 |
|---|---|
| `EOS_PRODUCT_ID` | 受け取った Product ID |
| `EOS_SANDBOX_ID` | 受け取った Sandbox ID |
| `EOS_DEPLOYMENT_ID` | 受け取った Deployment ID |
| `EOSG_ZIP_URL` | EOSG の Releases の zip の URL（下の 3.） |
| `EOSG_ZIP_SHA256` | その zip の SHA-256 |

**Secrets**（依頼者が自分で入れる）:
| 名前 | 値 |
|---|---|
| `EOS_CLIENT_ID` | 1-2 の Client ID |
| `EOS_CLIENT_SECRET` | 1-2 の Client Secret |
| `EOS_ENCRYPTION_KEY` | 64 文字の16進数（PowerShell: `-join ((1..32) \| % { '{0:x2}' -f (Get-Random -Max 256) })`）。一度決めたら変えない |

### 3. EOSG プラグイン（https://github.com/3ddelano/epic-online-services-godot/releases）
1. **Godot 4.5 で使える版**を選ぶ（新しい版は Godot 4.6 向けのことがある。リリースノートの対応版を確かめる）。
2. Windows 用が入った zip の URL を `EOSG_ZIP_URL` に、zip の SHA-256 を `EOSG_ZIP_SHA256` に。
3. EOS SDK のライセンス（Epic の利用規約）に同意が必要。依頼者に確認する。

### 4. CI で作って確かめる
- 値とプラグインがそろうと、CI が `config/eos.local.cfg` を書き、プラグインと自動読み込み（HPlatform など10個）を足して書き出す。足りなければ「EOS なしで作ります」と出て、今までどおりの exe になる。
- 確かめること（docs/EOS.md「実機で確かめること」）: 2台でランクマッチ、見つからないときゲームサーバーに切り替わる、フレンド招待、EOS のボイス、称号が実績に記録される。
- MSIX: EOS の dll（`EOSSDK-Win64-Shipping.dll` など）が exe と同じフォルダに入ること（CI は exe のフォルダをまるごと MSIX に入れる）。

## 実績は「統計で解除」（2026-11-25）
統計を使わない実績を解除できるのは GameServer のクライアントだけ（ポータルの表示）。ゲームは GameClient なので、
称号ごとに統計 `titleT001`〜`titleT155`（集計 MAX）を作り、ゲームは称号を取ると 1 を送る（`scripts/eos_matchmaker.gd` の `unlock_achievements`）。
実績 `t001`〜は「その統計が 1 以上」で自動で解除される。名前・説明は英語（既定）・ja・zh-Hans・ko。アイコンは仮（★の数の色）。
称号を足したら、ZIP を作り直してもう一度インポートする（定義はまるごと置きかわる。プレイヤーの記録は残る）。

## EOSG 2.3.1 の値（Variables）
| 名前 | 値 |
|---|---|
| `EOSG_ZIP_URL` | `https://github.com/3ddelano/epic-online-services-godot/releases/download/2.3.1/epic-online-services-godot-all-56238973e2cd7ac9ac99ca14f88934465f0a8997.zip` |
| `EOSG_ZIP_SHA256` | `45130948bf74f50cae3653fa4c051d0fa7333c1842b3b8e13a1d3affef3b6a16` |

（CI は Linux でインポートするので、全プラットフォーム入りの all の zip にした。SHA-256 は GitHub のリリースの表示）
## Anti-Cheat について（要件#135）
入れない。ネイティブ SDK とランチャー（ブートストラップ）の組み込みが必要で Godot・MSIX では手間が大きく、
勝敗・レート・判定はすでにサーバーが決めているので効果が小さい。
