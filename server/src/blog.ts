// 紹介サイトのガイド・ブログ（要件#125）。管理画面で Markdown で書き、言語ごとに見出しと本文を持つ。
// 「サイトに反映」で、リポジトリの site/ を写したものに記事のページ（言語ごと・記事ごとのふつうの HTML）を足し、
// Cloudflare Pages に直接アップロードする（wrangler pages deploy。検索エンジンが中身を読める形）。
// 記事の HTML はサーバーで作る。Markdown の中の HTML は使えない（すべて文字として出す）。リンクは https と / で始まるものだけ。
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { config } from "./config.ts";
import { openDb } from "./db.ts";
import { readNoticeImage } from "./notices.ts";

export const POST_LANGS = ["ja", "en", "zh", "ko"] as const;
export type PostLang = (typeof POST_LANGS)[number];
export const POST_KINDS = ["guide", "blog"] as const;
export type PostKind = (typeof POST_KINDS)[number];

export interface Post {
  id: number;
  slug: string;
  kind: PostKind;
  published: boolean;
  created_at: number;
  updated_at: number;
  published_at: number;
  title: Record<PostLang, string>;
  body: Record<PostLang, string>;
}

export class PostError extends Error {}

const SLUG = /^[a-z0-9][a-z0-9-]{0,59}$/;

let ready = false;
function db() {
  const d = openDb();
  if (!ready) {
    d.exec(`CREATE TABLE IF NOT EXISTS posts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      slug TEXT NOT NULL UNIQUE,
      kind TEXT NOT NULL,
      published INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      published_at INTEGER NOT NULL DEFAULT 0,
      title_ja TEXT NOT NULL DEFAULT '', title_en TEXT NOT NULL DEFAULT '', title_zh TEXT NOT NULL DEFAULT '', title_ko TEXT NOT NULL DEFAULT '',
      body_ja TEXT NOT NULL DEFAULT '', body_en TEXT NOT NULL DEFAULT '', body_zh TEXT NOT NULL DEFAULT '', body_ko TEXT NOT NULL DEFAULT ''
    )`);
    ready = true;
  }
  return d;
}

function rowToPost(r: Record<string, unknown>): Post {
  const t = {} as Record<PostLang, string>;
  const b = {} as Record<PostLang, string>;
  for (const l of POST_LANGS) {
    t[l] = String(r[`title_${l}`] ?? "");
    b[l] = String(r[`body_${l}`] ?? "");
  }
  return {
    id: Number(r.id), slug: String(r.slug), kind: (POST_KINDS as readonly string[]).includes(String(r.kind)) ? (r.kind as PostKind) : "blog",
    published: Number(r.published) === 1, created_at: Number(r.created_at), updated_at: Number(r.updated_at), published_at: Number(r.published_at), title: t, body: b,
  };
}

export function listPosts(): Post[] {
  return (db().prepare("SELECT * FROM posts ORDER BY published_at DESC, created_at DESC").all() as Array<Record<string, unknown>>).map(rowToPost);
}

export function getPost(id: number): Post | null {
  const r = db().prepare("SELECT * FROM posts WHERE id = ?").get(id) as Record<string, unknown> | undefined;
  return r ? rowToPost(r) : null;
}

const clean = (v: unknown, n: number) => (typeof v === "string" ? v.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "").slice(0, n) : "");

/** 記事を作る・直す（id が無ければ作る）。戻り値は記事 */
export function savePost(input: Record<string, unknown>): Post {
  const slug = clean(input.slug, 60).trim().toLowerCase();
  if (!SLUG.test(slug)) throw new PostError("記事の URL 名は、英小文字・数字・ハイフンだけ（60文字まで。例 how-to-play）にしてください");
  const kind = (POST_KINDS as readonly string[]).includes(String(input.kind)) ? (input.kind as PostKind) : null;
  if (!kind) throw new PostError("種類（ガイド・ブログ）を選んでください");
  const title = {} as Record<PostLang, string>;
  const body = {} as Record<PostLang, string>;
  for (const l of POST_LANGS) {
    title[l] = clean(input[`title_${l}`], 120).trim();
    body[l] = clean(input[`body_${l}`], 40000);
  }
  if (!POST_LANGS.some((l) => title[l] !== "" && body[l].trim() !== "")) throw new PostError("どれか1つの言語で、見出しと本文を入れてください");
  const id = Number(input.id ?? 0);
  const now = Date.now();
  const dup = db().prepare("SELECT id FROM posts WHERE slug = ? AND id != ?").get(slug, id) as { id: number } | undefined;
  if (dup) throw new PostError("その URL 名はほかの記事が使っています");
  const cols = POST_LANGS.flatMap((l) => [`title_${l}`, `body_${l}`]);
  const vals = POST_LANGS.flatMap((l) => [title[l], body[l]]);
  if (id > 0) {
    if (!getPost(id)) throw new PostError("その記事はありません");
    db().prepare(`UPDATE posts SET slug = ?, kind = ?, updated_at = ?, ${cols.map((c) => `${c} = ?`).join(", ")} WHERE id = ?`).run(slug, kind, now, ...vals, id);
    return getPost(id)!;
  }
  const r = db().prepare(`INSERT INTO posts (slug, kind, created_at, updated_at, ${cols.join(", ")}) VALUES (?, ?, ?, ?, ${cols.map(() => "?").join(", ")})`).run(slug, kind, now, now, ...vals);
  return getPost(Number(r.lastInsertRowid))!;
}

export function setPostPublished(id: number, on: boolean): void {
  const p = getPost(id);
  if (!p) throw new PostError("その記事はありません");
  db().prepare("UPDATE posts SET published = ?, published_at = ? WHERE id = ?").run(on ? 1 : 0, on && p.published_at === 0 ? Date.now() : p.published_at, id);
}

export function deletePost(id: number): void {
  db().prepare("DELETE FROM posts WHERE id = ?").run(id);
}

// ---------------------------------------------------------------- Markdown → HTML（安全なものだけ）

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
const IMAGE_NAME = /^[0-9a-f]{32}\.(png|jpg)$/;

function safeHref(u: string): string | null {
  if (/^https:\/\/[^\s"'<>]+$/.test(u)) return u;
  if (/^\/[^\s"'<>]*$/.test(u) && !u.startsWith("//")) return u;
  if (/^#[\w-]+$/.test(u)) return u;
  return null;
}

/** 1行の中の書式（太字・斜体・コード・リンク・画像）。入力はまだ逃がしていない文字 */
function inline(text: string, images: Set<string>): string {
  const codes: string[] = [];
  let s = text.replace(/`([^`]+)`/g, (_, c: string) => {
    codes.push(`<code>${esc(c)}</code>`);
    return `\u0000${codes.length - 1}\u0000`;
  });
  s = esc(s);
  // 画像: ![説明](image:<名前>)（管理画面で載せた画像だけ）
  s = s.replace(/!\[([^\]]*)\]\(image:([0-9a-f]{32}\.(?:png|jpg))\)/g, (_, alt: string, name: string) => {
    images.add(name);
    return `<img src="/assets/blog/${name}" alt="${alt}" loading="lazy">`;
  });
  // それ以外の画像（外のサイトの画像など）は出さず、説明の文だけにする（サイトの CSP も外の画像を読まない）
  s = s.replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1");
  s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (m, label: string, href: string) => {
    const h = safeHref(href.replace(/&amp;/g, "&"));
    if (!h) return label;
    const ext = h.startsWith("https://");
    return `<a href="${esc(h)}"${ext ? ' rel="noopener"' : ""}>${label}</a>`;
  });
  s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>").replace(/(^|[^*])\*([^*\s][^*]*)\*/g, "$1<em>$2</em>");
  return s.replace(/\u0000(\d+)\u0000/g, (_, i: string) => codes[Number(i)]);
}

/** Markdown を HTML に。見出し（## ・###）・段落・箇条書き・番号つき・引用・区切り線・コードのかたまり。使った画像の名前も返す */
export function renderMarkdown(md: string): { html: string; images: string[] } {
  const images = new Set<string>();
  const out: string[] = [];
  const lines = md.replace(/\r\n?/g, "\n").split("\n");
  let para: string[] = [];
  let list: { tag: "ul" | "ol"; items: string[] } | null = null;
  let quote: string[] = [];
  const flush = () => {
    if (para.length) out.push(`<p>${para.map((l) => inline(l, images)).join("<br>")}</p>`);
    para = [];
    if (list) out.push(`<${list.tag}>${list.items.map((i) => `<li>${inline(i, images)}</li>`).join("")}</${list.tag}>`);
    list = null;
    if (quote.length) out.push(`<blockquote><p>${quote.map((l) => inline(l, images)).join("<br>")}</p></blockquote>`);
    quote = [];
  };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^```/.test(line)) {
      flush();
      const code: string[] = [];
      for (i++; i < lines.length && !/^```/.test(lines[i]); i++) code.push(lines[i]);
      out.push(`<pre><code>${esc(code.join("\n"))}</code></pre>`);
      continue;
    }
    const h = /^(#{1,4})\s+(.+)$/.exec(line);
    if (h) {
      flush();
      // ページの見出し（h1）は記事の題なので、本文の見出しは h2 から
      const level = Math.min(4, Math.max(2, h[1].length + 1));
      out.push(`<h${level}>${inline(h[2].trim(), images)}</h${level}>`);
      continue;
    }
    if (/^\s*(-{3,}|\*{3,})\s*$/.test(line)) {
      flush();
      out.push("<hr>");
      continue;
    }
    const ul = /^\s*[-*]\s+(.+)$/.exec(line);
    const ol = /^\s*\d+[.)]\s+(.+)$/.exec(line);
    if (ul || ol) {
      const tag = ul ? "ul" : "ol";
      if (para.length || quote.length || (list && list.tag !== tag)) flush();
      if (!list) list = { tag, items: [] };
      list.items.push((ul ?? ol)![1]);
      continue;
    }
    const q = /^>\s?(.*)$/.exec(line);
    if (q) {
      if (para.length || list) flush();
      quote.push(q[1]);
      continue;
    }
    if (line.trim() === "") {
      flush();
      continue;
    }
    if (list || quote.length) flush();
    para.push(line.trim());
  }
  flush();
  return { html: out.join("\n"), images: [...images].filter((n) => IMAGE_NAME.test(n)) };
}

/** 記事の説明（検索結果・SNS 用）: 本文の最初の文字を 120 字まで */
function summary(md: string): string {
  return md.replace(/```[\s\S]*?```/g, " ").replace(/!\[[^\]]*\]\([^)]*\)/g, " ").replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/[#>*`_-]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 120);
}

// ---------------------------------------------------------------- サイトを作る

const L: Record<PostLang, Record<string, string>> = {
  ja: { page: "ガイド・ブログ", desc: "「カスハラ防衛線」の遊び方のガイドと、運営からのお知らせ・開発のブログ。", guide: "ガイド", blog: "ブログ", none: "まだ記事はありません。", back: "ガイド・ブログの一覧へ", date: "公開", only: "この記事は、ほかの言語でだけ読めます。" },
  en: { page: "Guides & Blog", desc: "How-to guides for Kasuhara Defense Line, plus news and development notes.", guide: "Guides", blog: "Blog", none: "No posts yet.", back: "Back to Guides & Blog", date: "Published", only: "This post is available in other languages only." },
  zh: { page: "指南・博客", desc: "《顾客骚扰防线》的玩法指南，以及运营通知和开发博客。", guide: "指南", blog: "博客", none: "还没有文章。", back: "返回指南・博客列表", date: "发布", only: "这篇文章只有其他语言的版本。" },
  ko: { page: "가이드·블로그", desc: "「카스하라 방어선」 플레이 가이드와 운영 공지·개발 블로그.", guide: "가이드", blog: "블로그", none: "아직 글이 없습니다.", back: "가이드·블로그 목록으로", date: "공개", only: "이 글은 다른 언어로만 읽을 수 있습니다." },
};
const HREFLANG: Record<PostLang, string> = { ja: "ja", en: "en", zh: "zh-Hans", ko: "ko" };

const fmtDate = (ms: number, lang: PostLang) => {
  const d = new Date(ms);
  const y = d.getUTCFullYear(), m = d.getUTCMonth() + 1, day = d.getUTCDate();
  if (lang === "en") return `${y}-${String(m).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
  if (lang === "ko") return `${y}년 ${m}월 ${day}일`;
  return `${y}年${m}月${day}日`;
};

/** リポジトリの site/ の場所 */
export function siteSource(): string {
  return process.env.SITE_SRC ?? path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "site");
}

/** サイトのドメイン（日本語のトップの canonical から読む） */
function siteOrigin(src: string): string {
  const s = fs.readFileSync(path.join(src, "ja", "index.html"), "utf-8");
  const m = /<link rel="canonical" href="(https?:\/\/[^/"]+)\/ja\/">/.exec(s);
  return m ? m[1] : "";
}

/** お問い合わせのページをひな形にして、見出し・説明・URL・本文を入れかえたページを作る */
function page(src: string, lang: PostLang, origin: string, o: { title: string; desc: string; path: string; main: string; alt: PostLang[]; langLinks: Record<PostLang, string> }): string {
  let s = fs.readFileSync(path.join(src, lang, "contact", "index.html"), "utf-8");
  const brand = /<title>[^|]*\| (.*?)<\/title>/.exec(s)?.[1] ?? "";
  const full = `${o.title} | ${brand}`;
  s = s.replace(/<title>.*?<\/title>/, `<title>${esc(full)}</title>`);
  s = s.replace(/(<meta (?:name="description"|property="og:description"|name="twitter:description") content=")[^"]*(")/g, `$1${esc(o.desc)}$2`);
  s = s.replace(/(<meta (?:property="og:title"|name="twitter:title") content=")[^"]*(")/g, `$1${esc(full)}$2`);
  s = s.replace(/(<link rel="canonical" href=")[^"]*(")/, `$1${origin}${o.path}$2`);
  s = s.replace(/(<meta property="og:url" content=")[^"]*(")/, `$1${origin}${o.path}$2`);
  // 言語ごとの別のページ（その言語の記事があるものだけ）
  s = s.replace(/<link rel="alternate" hreflang="[^"]+" href="[^"]*">\n?/g, "");
  const alts = o.alt.map((l) => `<link rel="alternate" hreflang="${HREFLANG[l]}" href="${origin}${o.path.replace(`/${lang}/`, `/${l}/`)}">`);
  if (o.alt.includes("en")) alts.push(`<link rel="alternate" hreflang="x-default" href="${origin}${o.path.replace(`/${lang}/`, "/en/")}">`);
  s = s.replace(/(<link rel="canonical"[^>]*>\n)/, `$1${alts.join("\n")}${alts.length ? "\n" : ""}`);
  // 上の案内: お問い合わせの「今のページ」の印を外す
  s = s.replace(/ aria-current="page"/g, "");
  // 言語の切り替え
  s = s.replace(/(<nav class="langs"[^>]*>)([\s\S]*?)(<\/nav>)/, (_m, a: string, inner: string, c: string) =>
    a + inner.replace(/href="\/(ja|en|zh|ko)\/contact\/"/g, (_x, l: PostLang) => `href="${o.langLinks[l]}"`) + c);
  s = s.replace(/<main id="main" class="doc">[\s\S]*?<\/main>/, () => `<main id="main" class="doc">\n<div class="wrap">\n<article class="sheet post">\n<span class="tape" aria-hidden="true"></span>\n${o.main}\n</article>\n</div>\n</main>`);
  return s;
}

/** 記事の一覧のページ（言語ごと）の本文 */
function listMain(lang: PostLang, posts: Post[]): string {
  const t = L[lang];
  const mine = posts.filter((p) => p.title[lang] !== "" && p.body[lang].trim() !== "");
  const sec = (kind: PostKind) => {
    const list = mine.filter((p) => p.kind === kind);
    if (list.length === 0) return "";
    return `<h2>${esc(t[kind])}</h2>\n<ul class="post-list">${list.map((p) =>
      `<li><a href="/${lang}/blog/${p.slug}/">${esc(p.title[lang])}</a> <time datetime="${new Date(p.published_at).toISOString().slice(0, 10)}">${esc(fmtDate(p.published_at, lang))}</time><p class="muted">${esc(summary(p.body[lang]))}</p></li>`).join("")}</ul>`;
  };
  const body = sec("guide") + sec("blog");
  return `<h1>${esc(t.page)}</h1>\n${body || `<p>${esc(t.none)}</p>`}`;
}

/**
 * サイトを out に作る: site/ を写し、ガイド・ブログのページ・画像・sitemap を足す。
 * posts を渡さなければ公開中の記事を使う（テスト・リポジトリのひな形づくり用に渡せる）
 */
export function buildSite(out: string, postsIn?: Post[]): { pages: number } {
  const src = siteSource();
  const origin = siteOrigin(src);
  const posts = (postsIn ?? listPosts().filter((p) => p.published)).filter((p) => p.published_at > 0 || postsIn !== undefined);
  fs.rmSync(out, { recursive: true, force: true });
  fs.cpSync(src, out, { recursive: true });
  let pages = 0;
  const urls: Array<{ path: string; alt: PostLang[]; at: number }> = [];
  for (const lang of POST_LANGS) {
    const links = Object.fromEntries(POST_LANGS.map((l) => [l, `/${l}/blog/`])) as Record<PostLang, string>;
    fs.mkdirSync(path.join(out, lang, "blog"), { recursive: true });
    fs.writeFileSync(path.join(out, lang, "blog", "index.html"), page(out, lang, origin, { title: L[lang].page, desc: L[lang].desc, path: `/${lang}/blog/`, main: listMain(lang, posts), alt: [...POST_LANGS], langLinks: links }));
    pages++;
  }
  urls.push({ path: "/ja/blog/", alt: [...POST_LANGS], at: Date.now() });
  const usedImages = new Set<string>();
  for (const p of posts) {
    const have = POST_LANGS.filter((l) => p.title[l] !== "" && p.body[l].trim() !== "");
    for (const lang of have) {
      const t = L[lang];
      const r = renderMarkdown(p.body[lang]);
      r.images.forEach((n) => usedImages.add(n));
      const links = Object.fromEntries(POST_LANGS.map((l) => [l, have.includes(l) ? `/${l}/blog/${p.slug}/` : `/${l}/blog/`])) as Record<PostLang, string>;
      const main = `<p class="muted"><span class="post-kind">${esc(t[p.kind])}</span>　${esc(t.date)}: <time datetime="${new Date(p.published_at).toISOString().slice(0, 10)}">${esc(fmtDate(p.published_at, lang))}</time></p>\n<h1>${esc(p.title[lang])}</h1>\n${r.html}\n<p class="post-back"><a href="/${lang}/blog/">← ${esc(t.back)}</a></p>`;
      const dir = path.join(out, lang, "blog", p.slug);
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, "index.html"), page(out, lang, origin, { title: p.title[lang], desc: summary(p.body[lang]) || t.desc, path: `/${lang}/blog/${p.slug}/`, main, alt: have, langLinks: links }));
      pages++;
    }
    if (have.length) urls.push({ path: `/${have[0]}/blog/${p.slug}/`, alt: have, at: p.updated_at });
  }
  // 画像（管理画面で載せたもの）
  if (usedImages.size) fs.mkdirSync(path.join(out, "assets", "blog"), { recursive: true });
  for (const n of usedImages) {
    const f = readNoticeImage(n);
    if (f) fs.writeFileSync(path.join(out, "assets", "blog", n), f.bytes);
  }
  // sitemap に足す（言語ごとの URL と hreflang）
  const smPath = path.join(out, "sitemap.xml");
  if (fs.existsSync(smPath) && origin !== "") {
    let sm = fs.readFileSync(smPath, "utf-8");
    sm = sm.replace(/  <url>\n    <loc>[^<]*\/blog\/[\s\S]*?<\/url>\n/g, "");
    const add = urls.flatMap((u) => u.alt.map((l) => {
      const loc = origin + u.path.replace(/^\/(ja|en|zh|ko)\//, `/${l}/`);
      const alt = u.alt.map((a) => `    <xhtml:link rel="alternate" hreflang="${HREFLANG[a]}" href="${origin}${u.path.replace(/^\/(ja|en|zh|ko)\//, `/${a}/`)}"/>`).join("\n");
      return `  <url>\n    <loc>${loc}</loc>\n${alt}\n    <lastmod>${new Date(u.at).toISOString().slice(0, 10)}</lastmod>\n  </url>\n`;
    })).join("");
    sm = sm.replace("</urlset>", add + "</urlset>");
    fs.writeFileSync(smPath, sm);
  }
  return { pages };
}

// ---------------------------------------------------------------- Cloudflare Pages に上げる

export interface DeployState {
  running: boolean;
  at: number;
  ok: boolean | null;
  log: string;
}
const state: DeployState = { running: false, at: 0, ok: null, log: "" };

export function deployState(): DeployState {
  return { ...state };
}

/**
 * サイトを作って Cloudflare Pages に上げる（同時に1つだけ。終わるまで待たない）。
 * 使うコマンドは wrangler（setup.sh が入れる）。テストでは SITE_DEPLOY_CMD で別のコマンドにできる
 */
export function startDeploy(opts: { project: string; accountId: string; token: string }): void {
  if (state.running) throw new PostError("いま反映しています。終わるまで待ってください");
  if (!/^[a-z0-9][a-z0-9-]{0,57}$/.test(opts.project)) throw new PostError("設定の「サイト」で、Cloudflare Pages のプロジェクト名を入れてください");
  if (!/^[0-9a-f]{32}$/.test(opts.accountId)) throw new PostError("設定の「サイト」で、Cloudflare のアカウント ID（32文字）を入れてください");
  if (opts.token === "") throw new PostError("設定の「サイト」で、Cloudflare の API トークンを入れてください");
  const varDir = config.dbPath === ":memory:" ? path.join(process.env.TMPDIR ?? "/tmp", "cushara-site") : path.dirname(config.dbPath);
  const out = path.join(varDir, "site_build");
  state.running = true;
  state.at = Date.now();
  state.ok = null;
  state.log = "";
  let built: { pages: number };
  try {
    built = buildSite(out);
  } catch (e) {
    state.running = false;
    state.ok = false;
    state.log = `サイトを作れませんでした: ${e instanceof Error ? e.message : String(e)}`;
    return;
  }
  const home = path.join(varDir, "wrangler_home");
  fs.mkdirSync(home, { recursive: true });
  const cmd = process.env.SITE_DEPLOY_CMD ?? "wrangler";
  const args = ["pages", "deploy", out, "--project-name", opts.project, "--branch", "main", "--commit-dirty=true"];
  const child = spawn(cmd, args, {
    env: {
      PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: home, XDG_CONFIG_HOME: path.join(home, ".config"),
      CLOUDFLARE_API_TOKEN: opts.token, CLOUDFLARE_ACCOUNT_ID: opts.accountId, WRANGLER_SEND_METRICS: "false", CI: "1",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  const add = (b: Buffer) => {
    // トークンがログに出ないように
    state.log = (state.log + b.toString("utf-8").split(opts.token).join("***")).slice(-6000);
  };
  child.stdout.on("data", add);
  child.stderr.on("data", add);
  const timer = setTimeout(() => child.kill("SIGTERM"), 5 * 60_000);
  child.on("error", (e) => {
    add(Buffer.from(`\n起動できませんでした（${cmd}）: ${e.message}。サーバー機に wrangler を入れてください（deploy/linux/setup.sh）`));
  });
  child.on("close", (code) => {
    clearTimeout(timer);
    state.running = false;
    state.ok = code === 0;
    add(Buffer.from(`\n（ページ ${built.pages} 枚。終了コード ${code}）`));
  });
}
