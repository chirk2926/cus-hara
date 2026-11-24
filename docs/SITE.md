# 紹介サイト（要件#105）

ゲームの紹介サイト。`site/` の中身がそのまま公開される静的なサイト（ビルドなし、フレームワークなし、JavaScript は自前の小さなファイルだけ）。
Godot がサイトの画像を取り込まないよう、`site/.gdignore`（空のファイル）を置いている。

## 1. 構成

| パス | 内容 |
|---|---|
| `site/index.html` | 入口。覚えている言語（`localStorage`）かブラウザの言語のページへ移る。JavaScript が無いときは4言語のリンクを出す。hreflang の x-default |
| `site/{ja,en,zh,ko}/index.html` | トップ（言語ごとに別のページ）。`zh` は簡体字（`lang="zh-Hans"`） |
| `site/{言語}/contact/` | お問い合わせ（メールだけ。フォームは無い） |
| `site/{言語}/terms/` | 利用規約（日本語が正本。ほかの言語は「日本語版が優先」と書いた翻訳） |
| `site/{言語}/blog/` | ガイド・ブログの一覧（5b節）。リポジトリには「まだ記事はありません」のひな形が入っていて、「サイトに反映」で記事つきのものに置きかわる |
| `site/{言語}/status/` | サーバーの状況。ゲームサーバーの `/api/v1/status` を読み、ゲームサーバー・AI のお客さん・声の対戦が「使えます／不安定／使えません／メンテナンス中／つながりません」かと、運営のお知らせ（管理画面の「サーバーの状況のお知らせ」）を出す。開いている間は1分ごとに確かめる。AI の会社やキーなどは出さない（サーバーが返さない） |
| `site/{言語}/privacy/` | プライバシーポリシー。`server/public/privacy.{言語}.html` の本文をそのまま写したもの（下の 5節） |
| `site/404.html` | 見つからないとき（Cloudflare Pages が自動で使う） |
| `site/sitemap.xml`・`site/robots.txt` | 検索エンジン用。sitemap には各ページの hreflang も入れている |
| `site/_headers` | Cloudflare Pages のヘッダー（CSP などのセキュリティ、画像・CSS・JS のキャッシュ） |
| `site/assets/css/site.css` | 見た目のすべて |
| `site/assets/js/site.js` | 仕掛けのすべて（4節）。`pick-lang.js` は入口の言語選び |
| `site/assets/img/` | 画像。`{言語}/*.webp` はスクリーンショット（640px と 1280px）、`og-{言語}.jpg` は SNS 用（1200×630）、`hero-*.webp`・`staff.webp`・アイコン |

フォントは Google Fonts から読む（`display=swap`。日本語・中国語・韓国語は Google が文字の範囲ごとに分けて配るので、使う文字の分だけ読み込まれる）。
言語ごとの書体: 日本語・英語は Dela Gothic One / Yusei Magic / DotGothic16 / Noto Sans JP（ゲームと同じ）。中国語は ZCOOL QingKe HuangYou / ZCOOL KuaiLe / Noto Sans SC、韓国語は Black Han Sans / Jua / Noto Sans KR（Dela Gothic One などに簡体字・ハングルが無いため）。すべて SIL OFL 1.1。

デザインは `docs/UI_GUIDE.md` に合わせた「お店の備品」: 求人ポスター、従業員証、レシート、お客様表示（液晶）、値札、名札、コルクボード、シャッター、インデックスの耳（言語の切り替え）。色は紙・インク・朱 `#d23f2f`・黄 `#ffd23f` だけで、グラデーション・ぼかし影・半透明のパネルは使わない。

## 2. Cloudflare Pages で公開する

1. Cloudflare のダッシュボード → Workers & Pages → 作成 → Pages → Git に接続 → このリポジトリを選ぶ。
2. ビルドの設定:
   - 本番のブランチ: 公開に使うブランチ（いまは `claude/wizardly-keller-c3rj2v`）
   - フレームワーク: なし / **ビルドコマンド: 空** / **ビルドの出力ディレクトリ: `site`**
3. 保存すると `https://<プロジェクト名>.pages.dev` で公開される。独自ドメインは Pages の「カスタムドメイン」から。
4. 公開するドメインが決まったら 3節で書きかえて push する。

Git に接続しない場合は `npx wrangler pages deploy site --project-name <名前>` でも上げられる。

## 3. 仮の値を書きかえる（ドメイン・Store・ゲームサーバー・メール）

仮の値は次の4つ。`tools/site_set_domain.py` がまとめて書きかえる（いまの値は site/ の中から読み取るので、何度でも実行できる）。

| 値 | いまの仮の値 | 使っている所 |
|---|---|---|
| サイトのドメイン | `https://example.pages.dev` | canonical・hreflang・OGP の画像と URL・JSON-LD・sitemap.xml・robots.txt |
| Microsoft Store のページ | `https://apps.microsoft.com/detail/XXXXXXXXXXXX` | 「Microsoft Store で入手」のボタン（各トップに2つ）・JSON-LD の offers |
| ゲームサーバー | `https://game.example.com` | プライバシーポリシーのページの「ゲーム内と同じページ」へのリンク（`/privacy?lang=xx`）、サーバーの状況のページが読む `/api/v1/status`、`_headers` の CSP の `connect-src` |
| 連絡先メール | 〔連絡先メールアドレス〕（黄色の印） | フッター・お問い合わせ・利用規約・プライバシーポリシー |

```bash
python3 tools/site_set_domain.py --show                     # いまの値を見る
python3 tools/site_set_domain.py --domain https://example.com
python3 tools/site_set_domain.py --store-url https://apps.microsoft.com/detail/9NXXXXXXXXXX
python3 tools/site_set_domain.py --game-server https://game.example.net
python3 tools/site_set_domain.py --email support@example.net
```

ほかに手で直すもの:
- **配信が始まったら**「近日配信予定です。配信が始まるまで、リンク先のページは開けません」などの一文（各トップの `cta-note` と `get_p`、`desc`・`specline` の「無料（予定）」）を消す・直す。OG 画像の「近日配信」は `site/assets/img/og-*.jpg`（作り直すときは同じ大きさ 1200×630）。
- **価格**: 790円（予定）の有料だが、サイトには価格を載せない（依頼者の決定。要件#120）。「アプリ内の購入はありません」とだけ書き、JSON-LD の offers にも価格を入れていない。価格はストアのページに出る。
- **コンビニを開けたら**: `#konbini` の章（シャッター）を、ふつうの紹介に書きかえる。クレーンの景品「コンビニ」も同じ章へ飛ぶ。
- `sitemap.xml` の `lastmod` は 2026-11-19。大きく書きかえたら日付を直す。

## 4. 仕掛け（どこにあるか）

すべて `prefers-reduced-motion`（動きを減らす設定）では動かない／すぐ移動する。キーボード（Tab・Enter）でも使え、JavaScript が無くても中身は読める。

| 仕掛け | 中身 | コード |
|---|---|---|
| 従業員証がゆれる | トップの右上にぶら下がった従業員証。読み込み時・マウスを乗せたとき・押したときに、少しゆれて止まる | `site.js` の 1、CSS `.idcard` / `@keyframes swing` |
| クレーンゲームのフロア案内 | 景品（ひよこ・くま…）を押すと、アームが動いてつかみ、取出口へ運んでからその章へ移る。中身はふつうのページ内リンク（`<a href="#play">`） | `site.js` の 2、CSS `.crane` |
| 印字されるレシート | 「あそびかた」のレシートが、スクロールに合わせてプリンターから出てくる | `site.js` の 3、CSS `.receipt`（`--p` が 0〜1） |
| お客様表示（怒りメーター） | クレーン大損男のセリフと、イカリ・ナットクの液晶。見えている間イカリが少しずつ上がり、接客用語のタグや店の行動を押すと変わる。謝ってばかりだとイカリが上がる、「全額返金」は屈服。会話（チャット）ではなく、決まったボタンだけ | `site.js` の 4、CSS `.demo` |
| コルクボード | 押しピンで留めたスクリーンショット。押すと `<dialog>` で大きく見られる（JavaScript が無ければ画像そのものを開く） | `site.js` の 5、CSS `.cork` / `.lightbox` |
| シャッター | 近日オープンのコンビニ。マウスを乗せる・「のぞく」ボタンでシャッターが少し上がる | `site.js` の 6、CSS `.shutter-box` |
| 値札・名札 | 特徴は値札（穴とひも付き）、対戦の役は名札 | CSS `.pricetag`・`.nametag` |

改行の扱い: 日本語は `word-break: auto-phrase`（文節で折り返す）、韓国語は `word-break: keep-all`、全体に `line-break: strict` と `overflow-wrap: break-word`、見出しは `text-wrap: balance`、本文は `text-wrap: pretty`。メールアドレスなど長い英数字だけ `.url` で折り返す。

## 5. プライバシーポリシーと利用規約

- プライバシーポリシーの正本は、ゲームサーバーが配る `server/public/privacy.*.html`（ゲームの中からはこちらを開く）。サイトの `site/{言語}/privacy/` は、その本文（`<main>` の中）をそのまま写して、サイトの見た目にしたもの。**サーバー側を直したら、サイト側にも同じ文を写す**（表は `<div class="table-scroll">` で包み、【連絡先メールアドレス】は `<span class="mail ph">` にする）。
- 利用規約は今回の下書き（2026年11月19日 制定）。**公開の前に、法律の専門家に確認してもらうこと。** 管轄は「運営者の住所地を管轄する地方裁判所」（第14条。要件#120）。料金は第2条（有料。購入・返金は Microsoft Store の決まりに従う）。ゲームの中の事実（ゲーム内の課金なし、HP・CUS はお金の価値が無い、対戦の禁止事項と対応、退職で削除、コンビニは準備中）と、プライバシーポリシー 3節・6節に合わせてある。規約を変えたら4言語とも直す（日本語が正本）。

## 5b. ガイド・ブログ（要件#125）
- 管理画面の「ガイド・ブログ」で記事を Markdown で書く（種類はガイド・ブログ、URL 名は英小文字・数字・ハイフン）。言語ごとに見出しと本文を入れ、入れた言語のページだけができる（`/{言語}/blog/<URL名>/`）。一覧は `/{言語}/blog/`。フッターに「ガイド・ブログ」のリンク。
- 使える書き方: 見出し（`#`〜`###`。本文では h2〜h4）、段落、**太字**、*斜体*、`コード`、箇条書き・番号つき、引用、区切り線、コードのかたまり、リンク（`https://`・`/` で始まるものだけ）、画像（エディタの「画像を入れる」で載せたものだけ。`![説明](image:<名前>)`）。HTML は書けない（文字として出る）。
- 「公開にする」→「サイトに反映」で、サーバー機がリポジトリの `site/`（サーバー機にある版）を写し、公開中の記事のページ・画像・sitemap を足して、`wrangler pages deploy` で Cloudflare Pages に**直接アップロード**する（ふつうの HTML なので検索エンジンが中身を読める。反映は1〜2分）。下書き・非公開・消した記事は、次に反映したときにサイトから消える。
- 準備（最初の1回）:
  1. Cloudflare のダッシュボード → Workers & Pages → 作成 → Pages →「直接アップロード（Upload assets）」でプロジェクトを作る（Git に接続したプロジェクトには直接アップロードできない。2節の Git 接続は使わない）。カスタムドメイン `cus.mgc-sv.com` をこのプロジェクトにつなぐ。
  2. API トークンを作る（マイプロフィール → API トークン → カスタム →「アカウント: Cloudflare Pages: 編集」だけ）。
  3. 管理画面の 設定 →「サイト」に、プロジェクト名・アカウント ID（32文字）・API トークンを入れる。
  4. サーバー機に wrangler を入れる（`deploy/linux/setup.sh` を流し直せば入る）。
- サイトの見た目を直したときも、サーバーを更新（`sudo cushara-update prod`）してから「サイトに反映」を押すと出る。
- ローカルで作りを確かめるテスト: `server/test/blog.test.ts`（Markdown の安全さ・ページ・sitemap・反映のコマンド）。

## 6. 言語を足す

1. `site/ja/` を `site/<新しい言語>/` に丸ごと写し、`lang`・`<title>`・`description`・本文・`og:locale` を訳す。
2. 4つ（以上）の全ページの `<link rel="alternate" hreflang=...>` と、ヘッダーの言語の耳（`<nav class="langs">`）に新しい言語を足す。`sitemap.xml` にも足す。
3. `site/assets/js/pick-lang.js` の `have` に言語を足す。入口の `site/index.html` と `404.html` のリンクにも足す。
4. スクリーンショットを `site/assets/img/<言語>/` に置く（`docs/store/` か `docs/screenshots/` から、幅 640 と 1280 の WebP。名前は他の言語と同じ）。OG 画像 `og-<言語>.jpg` も作る。
5. その言語の書体に Google Fonts の書体が要るなら、そのページの `fonts.googleapis.com` のリンクと、`site.css` の `:lang(..)` の書体を足す。

## 7. 確かめたこと（2026-11-19）

Playwright（Chromium）で、4言語 × 4ページ（トップ・お問い合わせ・規約・プライバシー）× 幅 360 / 768 / 1280 / 1920 を開き、横にはみ出さない・コンソールのエラーが無い・画像がすべて読める・フォントが読める、を確かめ、画面を見て改行・重なりを直した。hreflang・canonical・sitemap の URL が全ページでそろっていることも確かめた。
