// ガイド・ブログ（要件#125）: 記事の保存、Markdown の安全な変換、サイトのページづくり、反映のコマンド
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

process.env.DB_PATH = ":memory:";
const blog = await import("../src/blog.ts");

test("Markdown: HTML は文字として出し、危ないリンクは外す。見出し・箇条書き・画像（載せたものだけ）", () => {
  const r = blog.renderMarkdown([
    "# 見出し", "<script>alert(1)</script>", "**太字** と *斜体* と `<b>コード</b>`",
    "- いち", "- に", "", "1. ひとつ", "", "> 引用",
    "[よい](https://example.com) [わるい](javascript:alert(1)) [中](/ja/terms/)",
    "![説明](image:0123456789abcdef0123456789abcdef.png) ![外](https://evil.example/x.png)",
    "```", "<i>そのまま</i>", "```",
  ].join("\n"));
  assert.ok(!r.html.includes("<script>"), r.html);
  assert.ok(r.html.includes("&lt;script&gt;"));
  assert.ok(r.html.includes("<h2>見出し</h2>"), "本文の見出しは h2 から");
  assert.ok(r.html.includes("<strong>太字</strong>") && r.html.includes("<em>斜体</em>"));
  assert.ok(r.html.includes("<code>&lt;b&gt;コード&lt;/b&gt;</code>"));
  assert.ok(r.html.includes("<ul><li>いち</li><li>に</li></ul>") && r.html.includes("<ol><li>ひとつ</li></ol>"));
  assert.ok(r.html.includes('<a href="https://example.com" rel="noopener">よい</a>'));
  assert.ok(!r.html.includes("javascript:"));
  assert.ok(r.html.includes('<a href="/ja/terms/">中</a>'));
  assert.ok(r.html.includes('src="/assets/blog/0123456789abcdef0123456789abcdef.png"'));
  assert.ok(!r.html.includes("evil.example/x.png\""), "外の画像は出さない");
  assert.deepEqual(r.images, ["0123456789abcdef0123456789abcdef.png"]);
  assert.ok(r.html.includes("<pre><code>&lt;i&gt;そのまま&lt;/i&gt;</code></pre>"));
});

test("記事: URL 名の決まり・同じ URL 名は断る・公開・サイトのページ（書いた言語だけ）", () => {
  assert.throws(() => blog.savePost({ slug: "Bad Slug", kind: "guide", title_ja: "a", body_ja: "b" }), /URL 名/);
  const p = blog.savePost({ slug: "how-to-play", kind: "guide", title_ja: "遊び方", body_ja: "## はじめに\n**キレる前に**返事をする。", title_en: "How to play", body_en: "Reply before they snap." });
  assert.throws(() => blog.savePost({ slug: "how-to-play", kind: "blog", title_ja: "x", body_ja: "y" }), /ほかの記事/);
  blog.savePost({ slug: "draft-only", kind: "blog", title_ja: "下書き", body_ja: "まだ" });
  blog.setPostPublished(p.id, true);
  const out = fs.mkdtempSync(path.join(os.tmpdir(), "cushara-site-"));
  const r = blog.buildSite(out);
  assert.equal(r.pages, 4 + 2, "一覧4言語 + 記事2言語（日本語・英語）");
  const ja = fs.readFileSync(path.join(out, "ja", "blog", "how-to-play", "index.html"), "utf-8");
  assert.ok(ja.includes("<title>遊び方 | "));
  assert.ok(ja.includes("<strong>キレる前に</strong>"));
  assert.ok(ja.includes('hreflang="en" href="https://') && !ja.includes('hreflang="zh-Hans" href="https://cus.mgc-sv.com/zh/blog/how-to-play/"'), "書いていない言語の別ページは出さない");
  assert.ok(fs.existsSync(path.join(out, "en", "blog", "how-to-play", "index.html")));
  assert.ok(!fs.existsSync(path.join(out, "zh", "blog", "how-to-play")));
  assert.ok(!fs.existsSync(path.join(out, "ja", "blog", "draft-only")), "下書きは出さない");
  const list = fs.readFileSync(path.join(out, "ja", "blog", "index.html"), "utf-8");
  assert.ok(list.includes('href="/ja/blog/how-to-play/"') && list.includes("ガイド"));
  const sm = fs.readFileSync(path.join(out, "sitemap.xml"), "utf-8");
  assert.ok(sm.includes("/ja/blog/how-to-play/") && sm.includes("/en/blog/how-to-play/"));
  assert.equal(sm.split("/ja/blog/how-to-play/</loc>").length - 1, 1, "sitemap に同じ URL を2回入れない");
  fs.rmSync(out, { recursive: true, force: true });
});

test("サイトに反映: 設定が足りなければ断り、コマンドにはトークンを環境変数で渡してログには出さない", async () => {
  assert.throws(() => blog.startDeploy({ project: "", accountId: "0".repeat(32), token: "t" }), /プロジェクト名/);
  assert.throws(() => blog.startDeploy({ project: "cus", accountId: "x", token: "t" }), /アカウント ID/);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cushara-deploy-"));
  const fake = path.join(dir, "fake-wrangler.sh");
  fs.writeFileSync(fake, '#!/bin/sh\necho "args: $*"\necho "token: $CLOUDFLARE_API_TOKEN account: $CLOUDFLARE_ACCOUNT_ID"\n', { mode: 0o755 });
  process.env.SITE_DEPLOY_CMD = fake;
  blog.startDeploy({ project: "cus-site", accountId: "a".repeat(32), token: "secret-token-123" });
  for (let i = 0; i < 50 && blog.deployState().running; i++) await new Promise((r) => setTimeout(r, 100));
  const s = blog.deployState();
  assert.equal(s.ok, true, s.log);
  assert.ok(s.log.includes("--project-name cus-site"), s.log);
  assert.ok(!s.log.includes("secret-token-123"), "トークンはログに出さない");
  assert.ok(s.log.includes("account: " + "a".repeat(32)));
  delete process.env.SITE_DEPLOY_CMD;
  fs.rmSync(dir, { recursive: true, force: true });
});
