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
| Product ID / Sandbox ID / Deployment ID | 受け取り済み（依頼者のチャット）。GitHub の Variables にはまだ入っていない |
| Client ID / Client Secret | **まだ**（ポータルでクライアントを作る） |
| 暗号鍵（64文字の16進数） | **まだ**（依頼者が作って Secrets に入れる） |
| EOSG プラグイン | **まだ**（版を決め、zip の URL と SHA-256 を Variables に） |
| 実績（t001〜t155） | **まだ**（ポータルで登録） |
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

## Anti-Cheat について（要件#135）
入れない。ネイティブ SDK とランチャー（ブートストラップ）の組み込みが必要で Godot・MSIX では手間が大きく、
勝敗・レート・判定はすでにサーバーが決めているので効果が小さい。
