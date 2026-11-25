// 管理画面のスクリプト（要件#100）。プレイヤーの名前・通報のメモ・会話は、必ず文字（textContent）として入れる（HTML として解釈しない）。
"use strict";

let CSRF = "";

// ---------------------------------------------------------------- 部品

function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k === "class") el.className = v;
    else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else if (k === "value") el.value = v;
    else el.setAttribute(k, v === true ? "" : String(v));
  }
  for (const c of kids.flat()) {
    if (c === null || c === undefined || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}

function clear(el) {
  while (el.firstChild) el.firstChild.remove();
  return el;
}

function toast(text, err) {
  const m = document.getElementById("msg");
  m.textContent = text;
  m.className = "msg" + (err ? " err" : "");
  m.style.display = "block";
  clearTimeout(toast.t);
  toast.t = setTimeout(() => (m.style.display = "none"), 4000);
}

async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: { "content-type": "application/json", ...(method !== "GET" ? { "x-admin-csrf": CSRF } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
    credentials: "same-origin",
  });
  const data = await res.json().catch(() => ({}));
  if (res.status === 401 && path !== "/api/login") {
    showLogin();
    throw new Error(data.error || "ログインしてください");
  }
  if (!res.ok) throw new Error(data.error || `エラー（${res.status}）`);
  return data;
}

const fmtTime = (ms) => (ms ? new Date(ms).toLocaleString("ja-JP") : "—");
const fmtNum = (n) => Number(n || 0).toLocaleString("ja-JP");
const until = (u) => (u === -1 ? "永久" : u > Date.now() ? `${fmtTime(u)} まで` : "なし");
const REASONS = { abuse: "暴言・嫌がらせ", sexual: "性的な内容", personal_info: "個人情報", cheating: "ずる・不正", afk: "放置", other: "その他", hate: "差別・脅し", threat: "脅し" };

// ---------------------------------------------------------------- 画面の切り替え

const TABS = [
  ["status", "状態"], ["reports", "通報"], ["players", "プレイヤー"], ["matches", "対戦"], ["usage", "AIの料金"],
  ["notice", "お知らせ・メンテナンス"], ["blog", "ガイド・ブログ"], ["ai", "AIのAPI"], ["prompts", "AIの指示文"], ["backup", "バックアップ"], ["settings", "設定"], ["audit", "操作の記録"], ["account", "パスワード"],
];
let current = "status";

function buildTabs(openReports) {
  const nav = clear(document.getElementById("tabs"));
  for (const [id, label] of TABS) {
    nav.append(h("button", { class: id === current ? "on" : "", onclick: () => show(id) }, label, id === "reports" && openReports > 0 ? h("span", { class: "badge" }, openReports) : null));
  }
}

async function show(id) {
  current = id;
  for (const s of document.querySelectorAll("main section")) s.classList.toggle("on", s.id === "t-" + id);
  buildTabs(show.open || 0);
  try {
    await LOAD[id](document.getElementById("t-" + id));
  } catch (e) {
    toast(e.message, true);
  }
}

// ---------------------------------------------------------------- 状態

async function loadStatus(el) {
  const s = await api("GET", "/api/status");
  show.open = s.reports_open;
  buildTabs(s.reports_open);
  document.getElementById("ver").textContent = `v${s.version} / Node ${s.node}`;
  const kv = (k, v, cls) => h("div", { class: "kv" }, h("span", {}, k), h("b", { class: cls || "" }, v));
  const up = `${Math.floor(s.uptime_sec / 86400)}日 ${Math.floor((s.uptime_sec % 86400) / 3600)}時間 ${Math.floor((s.uptime_sec % 3600) / 60)}分`;
  clear(el).append(
    h("div", { class: "sheet" }, h("h2", {}, "いまのサーバー"),
      s.maintenance ? h("p", { class: "warn" }, "メンテナンス中（対戦を止めています）") : null,
      !s.trust_proxy ? h("p", { class: "warn" }, "TRUST_PROXY が 1 ではありません。Cloudflare Tunnel を使うときは 1 にしてください（プレイヤーの本当の IP で制限するため）") : null,
      h("div", { class: "grid" },
        kv("つながっている人", fmtNum(s.online.connected)), kv("対戦中", fmtNum(s.online.playing)), kv("マッチング待ち", fmtNum(s.online.queued)), kv("フレンドの部屋", fmtNum(s.online.rooms)),
        kv("プレイヤー（全部）", fmtNum(s.players.total)), kv("今日の新しい人", fmtNum(s.players.new_today)), kv("今日遊んだ人", fmtNum(s.players.active_today)), kv("今日の対戦", fmtNum(s.matches_today)),
        kv("未対応の通報", fmtNum(s.reports_open), s.reports_open > 0 ? "warn" : ""), kv("利用停止中", fmtNum(s.bans)),
        kv("AI（1人用）", s.ai.enabled ? s.ai.name : "使わない（キーワード判定）", s.ai.enabled ? "okc" : "warn"), kv("AI（対戦）", s.ai.versus !== "none" ? s.ai.versus : "使わない（キーワード判定）", s.ai.versus !== "none" ? "okc" : "warn"), kv("声の文字起こし", s.voice),
        kv("AIの呼び出し（起動から）", fmtNum(s.ai.calls)), kv("入力 / 出力トークン", `${fmtNum(s.ai.input)} / ${fmtNum(s.ai.output)}`),
        kv("動いている時間", up), kv("メモリ", `${s.memory_mb} MB`), kv("データベース", `${s.db_size_mb} MB`), kv("負荷（1・5・15分）", s.load.map((x) => x.toFixed(2)).join(" / ")),
      ),
      h("div", { class: "row" }, h("button", { class: "act", onclick: () => show("status") }, "読み込み直す"),
        h("button", { class: "act", onclick: async () => { const r = await api("POST", "/api/test-ai"); toast(r.message, !r.ok); } }, "AIの接続を確かめる"),
        h("button", { class: "act", onclick: async () => {
          if (!confirm("サーバーを再起動します。対戦中の人は切れます。よいですか？（systemd が起動し直します）")) return;
          await api("POST", "/api/restart"); toast("再起動しています… 10秒ほど待ってから読み込み直してください");
        } }, "サーバーを再起動"))),
  );
}

// ---------------------------------------------------------------- 通報

let reportFilter = "open";

async function loadReports(el) {
  const r = await api("GET", "/api/reports?status=" + reportFilter);
  const filter = h("div", { class: "row" }, ...[["open", "未対応"], ["handled", "対応済み"], ["dismissed", "問題なし"], ["all", "すべて"]].map(([k, l]) =>
    h("button", { class: k === reportFilter ? "main" : "act", onclick: () => { reportFilter = k; show("reports"); } }, l)));
  const rows = r.reports.map((x) => h("tr", {},
    h("td", {}, fmtTime(x.created_at)),
    h("td", {}, h("button", { class: "link", onclick: () => openPlayer(x.target_id) }, x.target_name || x.target_id), h("div", { class: "muted" }, `通報 ${x.target_reports} 件`)),
    h("td", {}, x.reporter_id === "system:moderation" ? h("span", { class: "pill open" }, "自動（不適切な発言）") : (x.reporter_name || x.reporter_id)),
    h("td", {}, h("span", { class: "pill" }, REASONS[x.reason] || x.reason), h("div", {}, x.note)),
    h("td", {}, x.match_id ? (x.has_log ? h("button", { class: "link", onclick: () => openLog(x.match_id) }, "会話を見る") : h("span", { class: "muted" }, "会話なし")) : "—"),
    h("td", {}, h("span", { class: "pill " + (x.status === "open" ? "open" : "") }, { open: "未対応", handled: "対応済み", dismissed: "問題なし" }[x.status] || x.status),
      x.status === "open" ? h("div", { class: "row" },
        h("button", { class: "act", onclick: () => resolveReport(x.id, "handled") }, "対応済みにする"),
        h("button", { class: "act", onclick: () => resolveReport(x.id, "dismissed") }, "問題なし")) : h("div", { class: "muted" }, x.handled_note)),
  ));
  clear(el).append(h("div", { class: "sheet" }, h("h2", {}, "通報"),
    h("p", { class: "muted" }, "対応（利用停止・名前のリセット・警告）は、相手の名前を押してプレイヤーの画面から。会話は通報された試合だけ30日保存しています。"),
    filter, h("table", {}, h("tr", {}, ...["日時", "相手", "通報した人", "理由・メモ", "会話", "状態"].map((t) => h("th", {}, t))), rows)));
}

async function resolveReport(id, status) {
  const note = prompt(status === "handled" ? "どう対応したか（記録用・任意）" : "問題なしにした理由（記録用・任意）", "") ?? null;
  if (note === null) return;
  await api("POST", `/api/reports/${id}`, { status, note });
  toast("更新しました");
  show("reports");
}

async function openLog(matchId) {
  const r = await api("GET", `/api/matches/${matchId}/log`);
  const l = r.log;
  const box = h("div", { class: "sheet" }, h("h2", {}, "試合の会話"), h("p", { class: "muted" }, `${l.kind} / ${l.format} / ${l.stage} / ${l.players.map((p) => p.name).join(" vs ")} / 終わり方: ${l.ended_reason || "—"}`),
    ...l.lines.map((x) => h("div", { class: "log-line" }, h("span", { class: "muted" }, `R${x.round} `), h("span", { class: "who" }, `${x.name}（${x.role === "staff" ? "店員" : "客"}${x.via === "voice" ? "・声" : ""}）`), x.text)),
    h("button", { class: "act", onclick: () => show(current) }, "閉じる"));
  const sec = document.getElementById("t-" + current);
  sec.prepend(box);
  box.scrollIntoView();
}

// ---------------------------------------------------------------- プレイヤー

let playerQuery = "";

async function loadPlayers(el) {
  const r = await api("GET", "/api/players?q=" + encodeURIComponent(playerQuery));
  const q = h("input", { placeholder: "名前・ID で探す", value: playerQuery, style: "min-width:280px" });
  q.addEventListener("keydown", (e) => { if (e.key === "Enter") { playerQuery = q.value; show("players"); } });
  clear(el).append(h("div", { class: "sheet" }, h("h2", {}, "プレイヤー"),
    h("div", { class: "row" }, q, h("button", { class: "act", onclick: () => { playerQuery = q.value; show("players"); } }, "探す")),
    h("table", {}, h("tr", {}, ...["名前", "レート", "勝-負-分", "通報", "利用停止", "最後に来た日"].map((t) => h("th", {}, t))),
      r.players.map((p) => h("tr", {},
        h("td", {}, h("button", { class: "link", onclick: () => openPlayer(p.id) }, p.name)),
        h("td", { class: "num" }, p.rating), h("td", { class: "num" }, `${p.wins}-${p.losses}-${p.draws}`),
        h("td", { class: "num " + (p.reports > 0 ? "warn" : "") }, p.reports),
        h("td", {}, until(p.banned_until) !== "なし" ? h("span", { class: "warn" }, "全部: " + until(p.banned_until)) : until(p.versus_banned_until) !== "なし" ? h("span", { class: "warn" }, "対戦: " + until(p.versus_banned_until)) : "—"),
        h("td", {}, fmtTime(p.last_seen)))))));
}

async function openPlayer(id) {
  current = "players";
  for (const s of document.querySelectorAll("main section")) s.classList.toggle("on", s.id === "t-players");
  buildTabs(show.open || 0);
  const r = await api("GET", "/api/players/" + id);
  const p = r.player;
  const el = clear(document.getElementById("t-players"));
  const reason = h("input", { placeholder: "理由（ゲームに出ます）", style: "min-width:320px" });
  const hours = h("select", {}, ...[[24, "24時間"], [72, "3日"], [168, "7日"], [720, "30日"]].map(([v, l]) => h("option", { value: v }, l)));
  const scope = h("select", {}, h("option", { value: "versus" }, "対戦だけ"), h("option", { value: "all" }, "全部（ログインも）"));
  const warn = h("textarea", { placeholder: "警告の文（次にゲームを開いたときに出ます）" });
  const act = async (type, extra) => {
    if (["ban", "suspend"].includes(type) && reason.value.trim() === "") return toast("理由を入れてください", true);
    if (type === "ban" && !confirm(`${p.name} を永久に利用停止にします。よいですか？`)) return;
    await api("POST", `/api/players/${id}/action`, { type, reason: reason.value, hours: Number(hours.value), scope: scope.value, ...extra });
    toast("実行しました");
    openPlayer(id);
  };
  const s = r.sanction;
  el.append(
    h("div", { class: "row" }, h("button", { class: "link", onclick: () => show("players") }, "← 一覧に戻る")),
    h("div", { class: "sheet" }, h("h2", {}, p.name),
      h("div", { class: "grid" },
        h("div", { class: "kv" }, h("span", {}, "ID"), h("b", {}, p.id)), h("div", { class: "kv" }, h("span", {}, "レート"), h("b", {}, p.rating)),
        h("div", { class: "kv" }, h("span", {}, "勝-負-分"), h("b", {}, `${p.wins}-${p.losses}-${p.draws}`)), h("div", { class: "kv" }, h("span", {}, "称号"), h("b", {}, p.title || "—")),
        h("div", { class: "kv" }, h("span", {}, "はじめて来た日"), h("b", {}, fmtTime(p.created_at))), h("div", { class: "kv" }, h("span", {}, "最後に来た日"), h("b", {}, fmtTime(p.last_seen))),
        h("div", { class: "kv" }, h("span", {}, "利用停止（全部）"), h("b", { class: until(s.bannedUntil) !== "なし" ? "warn" : "" }, until(s.bannedUntil))),
        h("div", { class: "kv" }, h("span", {}, "利用停止（対戦）"), h("b", { class: until(s.versusBannedUntil) !== "なし" ? "warn" : "" }, until(s.versusBannedUntil))),
        h("div", { class: "kv" }, h("span", {}, "まだ読まれていない警告"), h("b", {}, s.warnMessage || "—")),
        h("div", { class: "kv" }, h("span", {}, "この人がした通報"), h("b", {}, r.reports_by.n)),
        h("div", { class: "kv" }, h("span", {}, "対戦の同意"), h("b", {}, r.consent.version > 0 ? `第${r.consent.version}版（${fmtTime(r.consent.at)}）` : "なし")),
      ),
      h("h3", {}, "利用停止"),
      h("div", { class: "row" }, reason),
      h("div", { class: "row" }, scope, hours, h("button", { class: "act", onclick: () => act("suspend") }, "期間を決めて止める"),
        h("button", { class: "act", onclick: () => act("ban") }, "永久に止める（BAN）"), h("button", { class: "act", onclick: () => act("unban") }, "止めるのをやめる")),
      h("h3", {}, "名前・称号"),
      h("div", { class: "row" }, h("button", { class: "act", onclick: () => confirm("名前を「名無しのスタッフ」に戻します") && act("reset_name") }, "名前をリセット"),
        h("button", { class: "act", onclick: () => act("reset_title") }, "称号をはずす")),
      h("h3", {}, "警告"), warn, h("div", { class: "row" }, h("button", { class: "act", onclick: () => act("warn", { message: warn.value }) }, "警告を送る")),
    ),
    h("div", { class: "sheet" }, h("h2", {}, `この人への通報（${r.reports_against.length}）`),
      h("table", {}, r.reports_against.map((x) => h("tr", {}, h("td", {}, fmtTime(x.created_at)), h("td", {}, x.reporter_id === "system:moderation" ? "自動" : (x.reporter_name || x.reporter_id)),
        h("td", {}, h("span", { class: "pill" }, REASONS[x.reason] || x.reason), x.note), h("td", {}, { open: "未対応", handled: "対応済み", dismissed: "問題なし" }[x.status] || x.status))))),
    h("div", { class: "sheet" }, h("h2", {}, "最近の対戦"),
      h("table", {}, r.matches.map((m) => h("tr", {}, h("td", {}, fmtTime(m.created_at)), h("td", {}, `${m.p1_name} vs ${m.p2_name}`), h("td", {}, `${m.kind} / ${m.format}`),
        h("td", { class: "num" }, `${m.p1_points} - ${m.p2_points}`), h("td", {}, m.ended_reason), h("td", {}, m.has_log ? h("button", { class: "link", onclick: () => openLog(m.id) }, "会話") : ""))))),
    h("div", { class: "sheet" }, h("h2", {}, "この人への操作の記録"), r.history.length === 0 ? h("p", { class: "muted" }, "まだありません") :
      h("table", {}, r.history.map((x) => h("tr", {}, h("td", {}, fmtTime(x.at)), h("td", {}, x.detail))))),
  );
}

// ---------------------------------------------------------------- 対戦

async function loadMatches(el) {
  const r = await api("GET", "/api/matches");
  clear(el).append(h("div", { class: "sheet" }, h("h2", {}, "最近の対戦（100件）"),
    h("p", { class: "muted" }, "会話が見られるのは、通報された試合だけです（30日で消えます）。"),
    h("table", {}, h("tr", {}, ...["日時", "対戦", "種類", "点", "勝者", "終わり方", "会話"].map((t) => h("th", {}, t))),
      r.matches.map((m) => h("tr", {}, h("td", {}, fmtTime(m.created_at)),
        h("td", {}, h("button", { class: "link", onclick: () => openPlayer(m.p1) }, m.p1_name || "?"), " vs ", h("button", { class: "link", onclick: () => openPlayer(m.p2) }, m.p2_name || "?")),
        h("td", {}, `${m.kind} / ${m.format}`), h("td", { class: "num" }, `${m.p1_points} - ${m.p2_points}`),
        h("td", {}, m.winner === null ? "引き分け" : m.winner === m.p1 ? m.p1_name : m.p2_name), h("td", {}, m.ended_reason),
        h("td", {}, m.has_log ? h("button", { class: "link", onclick: () => openLog(m.id) }, "見る") : ""))))));
}

// ---------------------------------------------------------------- AI の料金

async function loadUsage(el) {
  const r = await api("GET", "/api/usage");
  const byDay = {};
  for (const x of r.rows) (byDay[x.day] = byDay[x.day] || []).push(x);
  const maxCost = Math.max(0.0001, ...Object.values(byDay).map((xs) => xs.reduce((a, x) => a + x.cost_usd, 0)));
  clear(el).append(h("div", { class: "sheet" }, h("h2", {}, "AIの料金の目安"),
    h("p", { class: "muted" }, "トークン数 × 料金表（設定の「AIの料金表」）から計算した目安です。本当の請求は、それぞれの会社（Anthropic・OpenAI・Google・DeepSeek）の管理ページで確かめてください。料金表に無いモデルは 0 円で数えます。"),
    h("div", { class: "grid" },
      h("div", { class: "kv" }, h("span", {}, `今月（${r.month}）`), h("b", {}, `$${r.month_cost_usd.toFixed(2)}`)),
      h("div", { class: "kv" }, h("span", {}, "このままだと月末に"), h("b", { class: r.over_budget ? "warn" : "" }, `$${r.projected_usd.toFixed(2)}`)),
      h("div", { class: "kv" }, h("span", {}, "上限の目安"), h("b", {}, r.budget_usd > 0 ? `$${r.budget_usd}` : "見ない")),
    ),
    r.over_budget ? h("p", { class: "warn" }, "上限の目安を超えそうです。設定で「サーバー全体の AI の呼び出し」を下げるか、モデルを Haiku にしてください。") : null,
    h("table", {}, h("tr", {}, ...["日", "モデル", "回数", "入力", "出力", "キャッシュ読み", "キャッシュ書き", "目安", ""].map((t, i) => h("th", { class: i >= 2 ? "num" : "" }, t))),
      Object.entries(byDay).flatMap(([day, xs]) => xs.map((x, i) => h("tr", {},
        h("td", {}, i === 0 ? day : ""), h("td", {}, x.model), h("td", { class: "num" }, fmtNum(x.calls)), h("td", { class: "num" }, fmtNum(x.input)),
        h("td", { class: "num" }, fmtNum(x.output)), h("td", { class: "num" }, fmtNum(x.cache_read)), h("td", { class: "num" }, fmtNum(x.cache_write)),
        h("td", { class: "num" }, `$${x.cost_usd.toFixed(4)}`),
        h("td", { style: "width:120px" }, h("div", { class: "bar" }, h("i", { style: `width:${Math.round((100 * x.cost_usd) / maxCost)}%` })))))))));
}

// ---------------------------------------------------------------- お知らせ・メンテナンス

const FONT_LABELS = { body: "本文（ふつう）", hand: "手書き", dot: "ドット文字", sign: "看板（極太）" };
const LANGS = [["ja", "日本語"], ["en", "English"], ["zh", "中文"], ["ko", "한국어"]];
const emptyNotice = () => ({ id: 0, title_ja: "", title_en: "", title_zh: "", title_ko: "", text_ja: "", text_en: "", text_zh: "", text_ko: "", font: "body", image: "" });
let noticeDraft = emptyNotice();
let noticeLang = "ja";

/** Markdown の一部（ゲームと同じ: 見出し・太字・斜体・コード・リンク・箇条書き・改行）を、文字として安全に表示する */
function mdToDom(md) {
  const box = h("div", {});
  const inline = (text) => {
    const out = [];
    const re = /(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`|\[[^\]]+\]\((https?:\/\/[^)\s]+)\))/g;
    let last = 0;
    let m;
    while ((m = re.exec(text)) !== null) {
      if (m.index > last) out.push(text.slice(last, m.index));
      const t = m[0];
      if (t.startsWith("**")) out.push(h("b", {}, t.slice(2, -2)));
      else if (t.startsWith("`")) out.push(h("code", {}, t.slice(1, -1)));
      else if (t.startsWith("[")) out.push(h("a", { href: m[2], target: "_blank", rel: "noopener noreferrer" }, t.slice(1, t.indexOf("]"))));
      else out.push(h("i", {}, t.slice(1, -1)));
      last = m.index + t.length;
    }
    if (last < text.length) out.push(text.slice(last));
    return out;
  };
  let list = null;
  for (const raw of md.split("\n")) {
    const line = raw.replace(/\s+$/, "");
    const hm = /^(#{1,3})\s+(.*)$/.exec(line);
    const lm = /^\s*[-*]\s+(.*)$/.exec(line);
    if (lm) {
      if (!list) { list = h("ul", {}); box.append(list); }
      list.append(h("li", {}, inline(lm[1])));
      continue;
    }
    list = null;
    if (hm) box.append(h("h" + hm[1].length, {}, inline(hm[2])));
    else if (line === "") box.append(h("div", { style: "height:8px" }));
    else box.append(h("div", {}, inline(line)));
  }
  return box;
}

async function imageDataUrl(name) {
  if (!name) return "";
  const r = await api("GET", "/api/notice_image/" + name);
  return `data:${r.type};base64,${r.data}`;
}

const imageCache = new Map();
async function cachedImage(name) {
  if (!imageCache.has(name)) imageCache.set(name, await imageDataUrl(name));
  return imageCache.get(name);
}

async function loadNotice(el) {
  const [a, st] = await Promise.all([api("GET", "/api/announcements"), api("GET", "/api/settings")]);
  const m = st.settings.find((x) => x.key === "maintenance");
  const mm = st.settings.find((x) => x.key === "maintenanceMessage");
  const mmsg = h("input", { value: mm.value, style: "width:100%" });
  const d = noticeDraft;
  // 言語のタブ
  const ltabs = h("div", { class: "row ltabs" }, ...LANGS.map(([k, l]) => h("button", { class: k === noticeLang ? "on" : "", onclick: () => { noticeLang = k; show("notice"); } },
    l, (d["title_" + k] || d["text_" + k]) ? " ●" : "")));
  const title = h("input", { placeholder: noticeLang === "ja" ? "見出し（必須）" : "見出し（空なら英語 → 日本語を出す）", value: d["title_" + noticeLang], style: "width:100%" });
  const body = h("textarea", { placeholder: "本文（Markdown）\n# 見出し\n**太字** *斜体* `コード`\n- 箇条書き\n[リンク](https://example.com)" });
  body.value = d["text_" + noticeLang];
  const font = h("select", {}, ...Object.entries(FONT_LABELS).map(([k, l]) => h("option", { value: k }, l)));
  font.value = d.font;
  const file = h("input", { type: "file", accept: "image/png,image/jpeg" });
  const preview = h("div", { class: "preview" });
  // 画像を読み込んでいる間に次の入力が来ても、古い描画を重ねない（レビュー3）。画像は一度読んだら覚えておく
  let gen = 0;
  const renderPreview = async () => {
    d["title_" + noticeLang] = title.value;
    d["text_" + noticeLang] = body.value;
    d.font = font.value;
    const my = ++gen;
    const img = d.image ? await cachedImage(d.image) : "";
    if (my !== gen) return;
    clear(preview);
    preview.style.fontFamily = `"G-${d.font}", sans-serif`;
    preview.append(h("h2", {}, title.value || d.title_ja || "（見出し）"));
    if (img) preview.append(h("img", { src: img, alt: "" }));
    preview.append(mdToDom(body.value || d.text_ja));
  };
  for (const x of [title, body]) x.addEventListener("input", renderPreview);
  font.addEventListener("change", renderPreview);
  file.addEventListener("change", async () => {
    const f = file.files[0];
    if (!f) return;
    if (f.size > 2 * 1024 * 1024) return toast("画像は 2MB までにしてください", true);
    const b64 = await new Promise((res) => { const r = new FileReader(); r.onload = () => res(String(r.result).split(",")[1]); r.readAsDataURL(f); });
    try {
      const up = await api("POST", "/api/announcements/image", { data: b64 });
      d.image = up.name;
      toast("画像を載せました");
      renderPreview();
    } catch (e) { toast(e.message, true); }
  });
  const save = h("button", { class: "main", onclick: async () => {
    await renderPreview();
    const payload = { ...d };
    try {
      if (d.id) await api("POST", `/api/announcements/${d.id}`, payload);
      else await api("POST", "/api/announcements", payload);
      toast(d.id ? "直しました" : "お知らせを出しました");
      noticeDraft = emptyNotice();
      noticeLang = "ja";
      show("notice");
    } catch (e) { toast(e.message, true); }
  } }, d.id ? "直して保存" : "お知らせを出す");
  const reset = d.id || d.title_ja || d.text_ja ? h("button", { class: "link", onclick: () => { noticeDraft = emptyNotice(); show("notice"); } }, d.id ? "直すのをやめる" : "消して書き直す") : null;
  clear(el).append(
    h("div", { class: "sheet" }, h("h2", {}, "メンテナンス"),
      h("p", {}, m.value ? h("span", { class: "warn" }, "いまメンテナンス中です（対戦を止めています。1人用は遊べます）") : "ふだんどおり動いています"),
      h("div", { class: "row" }, h("span", {}, "お知らせの文:"), mmsg),
      h("div", { class: "row" },
        h("button", { class: "main", onclick: async () => { await setSetting("maintenanceMessage", mmsg.value); await setSetting("maintenance", !m.value); show("notice"); } }, m.value ? "メンテナンスを終える" : "メンテナンスを始める"))),
    h("div", { class: "sheet" }, h("h2", {}, d.id ? `お知らせを直す（#${d.id}）` : "お知らせを書く"),
      h("p", { class: "muted" }, "タイトル画面に見出しが並び、押すと本文・画像が出ます（新しい5つまで）。言語ごとに書けます（空の言語は英語 → 日本語を出します）。本文は Markdown（見出し・太字・斜体・コード・箇条書き・リンク）。"),
      ltabs,
      h("div", { class: "editor" },
        h("div", {}, title, body,
          h("div", { class: "row" }, h("span", {}, "フォント:"), font),
          h("div", { class: "row" }, h("span", {}, "画像（PNG・JPEG、2MB まで）:"), file,
            d.image ? h("button", { class: "link", onclick: () => { d.image = ""; show("notice"); } }, "画像をはずす") : null),
          h("div", { class: "row" }, save, reset)),
        h("div", {}, h("div", { class: "muted" }, "プレビュー（ゲームでの見え方に近い）"), preview))),
    h("div", { class: "sheet" }, h("h2", {}, "出したお知らせ"),
      h("table", {}, a.announcements.map((x) => h("tr", {}, h("td", {}, fmtTime(x.created_at)),
        h("td", {}, h("b", {}, x.title_ja || "（見出しなし）"), h("div", { class: "muted" }, (x.text_ja || "").slice(0, 80)),
          h("div", { class: "muted" }, `${FONT_LABELS[x.font] || x.font}${x.image ? "・画像あり" : ""}${x.title_en || x.text_en ? "・EN" : ""}${x.title_zh || x.text_zh ? "・中" : ""}${x.title_ko || x.text_ko ? "・韓" : ""}`)),
        h("td", {}, x.active ? h("span", { class: "okc" }, "出している") : h("span", { class: "muted" }, "下げた")),
        h("td", {}, h("button", { class: "act", onclick: () => { noticeDraft = { ...emptyNotice(), ...x }; noticeLang = "ja"; show("notice"); } }, "直す"), " ",
          h("button", { class: "act", onclick: async () => { await api("POST", `/api/announcements/${x.id}`, { active: !x.active }); show("notice"); } }, x.active ? "下げる" : "出す"), " ",
          h("button", { class: "act", onclick: async () => { if (confirm("消しますか？")) { await api("POST", `/api/announcements/${x.id}`, { delete: true }); show("notice"); } } }, "消す")))))),
  );
  renderPreview();
}

// ---------------------------------------------------------------- 設定

async function setSetting(key, value) {
  const r = await api("POST", "/api/settings", { key, value });
  toast(r.restart ? "保存しました。この設定は再起動のあとに効きます" : "保存しました（すぐに効きます）");
  return r;
}

let settingsQuery = "";

/** 設定（要件#100: 見た目より使いやすさ）。探す・Enter で保存・変えた項目に印・まとめて保存 */
// ---------------------------------------------------------------- ガイド・ブログ（要件#125）

let blogEdit = null; // 書いている記事（null なら一覧）
let blogLang = "ja";
const KIND = { guide: "ガイド", blog: "ブログ" };

async function loadBlog(el) {
  const r = await api("GET", "/api/posts");
  clear(el);
  const dep = r.deploy;
  const depText = dep.running ? "反映しています…" : dep.ok === null ? "まだ反映していません" : dep.ok ? `反映しました（${fmtTime(dep.at)}）` : `反映できませんでした（${fmtTime(dep.at)}）`;
  const log = h("pre", { class: "muted", style: "white-space:pre-wrap;max-height:220px;overflow:auto;font-size:12px" }, dep.log || "");
  const deploy = h("button", { class: "main", disabled: dep.running, onclick: async () => {
    if (!confirm("公開中の記事で紹介サイトを作り直して、Cloudflare Pages に上げます。よいですか？")) return;
    try { await api("POST", "/api/site/deploy", {}); toast("反映を始めました"); } catch (e) { toast(e.message, true); }
    const poll = async () => { const s = await api("GET", "/api/site/deploy"); if (s.deploy.running) setTimeout(poll, 2000); else { show("blog"); toast(s.deploy.ok ? "反映しました" : "反映できませんでした（記録を見てください）", !s.deploy.ok); } };
    setTimeout(poll, 1500);
  } }, "サイトに反映");
  el.append(h("div", { class: "sheet" }, h("h2", {}, "ガイド・ブログ"),
    h("p", { class: "muted" }, "紹介サイトの「ガイド・ブログ」に出す記事を Markdown で書きます。言語ごとに見出しと本文を入れ、入れた言語のページだけができます。公開にしても、「サイトに反映」を押すまではサイトに出ません（反映すると、サイト全体をこのサーバーにある版で上げ直します）。上げる先は 設定 →「サイト」。"),
    h("div", { class: "row" }, h("button", { class: "act", onclick: () => { blogEdit = { id: 0, slug: "", kind: "guide", title: { ja: "", en: "", zh: "", ko: "" }, body: { ja: "", en: "", zh: "", ko: "" } }; blogLang = "ja"; renderBlogEditor(el); } }, "新しく書く"),
      deploy, h("span", { class: dep.ok === false ? "warn" : "muted" }, depText)),
    dep.log ? log : null));
  const tbl = h("table", {}, h("tr", {}, h("th", {}, "種類"), h("th", {}, "見出し"), h("th", {}, "URL 名"), h("th", {}, "言語"), h("th", {}, "状態"), h("th", {}, "更新"), h("th", {}, "")));
  for (const p of r.posts) {
    const langs = LANGS.filter(([k]) => p.title[k] && p.body[k]).map(([, l]) => l).join("・");
    tbl.append(h("tr", {}, h("td", {}, KIND[p.kind]), h("td", {}, p.title.ja || p.title.en || p.title.zh || p.title.ko), h("td", {}, p.slug), h("td", {}, langs),
      h("td", { class: p.published ? "okc" : "muted" }, p.published ? "公開" : "下書き"), h("td", {}, fmtTime(p.updated_at)),
      h("td", {},
        h("button", { class: "link", onclick: async () => { const g = await api("GET", `/api/posts/${p.id}`); blogEdit = g.post; blogLang = "ja"; renderBlogEditor(el); } }, "直す"),
        " ", h("button", { class: "link", onclick: async () => { await api("POST", `/api/posts/${p.id}`, { published: !p.published }); show("blog"); } }, p.published ? "下書きに戻す" : "公開にする"),
        " ", h("button", { class: "link", onclick: async () => { if (confirm("この記事を消しますか？（サイトからは、次に反映したときに消えます）")) { await api("POST", `/api/posts/${p.id}`, { delete: true }); show("blog"); } } }, "消す"))));
  }
  el.append(h("div", { class: "sheet" }, r.posts.length ? tbl : h("p", { class: "muted" }, "まだ記事はありません。")));
}

function renderBlogEditor(el) {
  const d = blogEdit;
  clear(el);
  const kind = h("select", {}, ...Object.entries(KIND).map(([k, l]) => h("option", { value: k }, l)));
  kind.value = d.kind;
  kind.addEventListener("change", () => (d.kind = kind.value));
  const slug = h("input", { value: d.slug, placeholder: "例 how-to-play（英小文字・数字・ハイフン）", style: "width:100%" });
  slug.addEventListener("input", () => (d.slug = slug.value));
  const ltabs = h("div", { class: "row ltabs" }, ...LANGS.map(([k, l]) => h("button", { class: k === blogLang ? "on" : "", onclick: () => { blogLang = k; renderBlogEditor(el); } }, l, d.title[k] && d.body[k] ? " ●" : "")));
  const title = h("input", { value: d.title[blogLang], placeholder: "見出し", style: "width:100%" });
  const body = h("textarea", { style: "width:100%;min-height:360px", placeholder: "本文（Markdown）\n## 見出し\n**太字** *斜体* `コード`\n- 箇条書き\n1. 番号つき\n> 引用\n[リンク](https://example.com)\n画像は下の「画像を入れる」で" });
  body.value = d.body[blogLang];
  const preview = h("div", { class: "preview" });
  const draw = () => { d.title[blogLang] = title.value; d.body[blogLang] = body.value; clear(preview).append(h("h2", {}, title.value || "（見出し）"), mdToDom(body.value.replace(/!\[([^\]]*)\]\(image:[^)]+\)/g, "（画像: $1）"))); };
  title.addEventListener("input", draw);
  body.addEventListener("input", draw);
  draw();
  const file = h("input", { type: "file", accept: "image/png,image/jpeg" });
  file.addEventListener("change", async () => {
    const f = file.files[0];
    if (!f) return;
    if (f.size > 2 * 1024 * 1024) return toast("画像は 2MB までにしてください", true);
    const b64 = await new Promise((res) => { const r = new FileReader(); r.onload = () => res(String(r.result).split(",")[1]); r.readAsDataURL(f); });
    try {
      const up = await api("POST", "/api/announcements/image", { data: b64 });
      const snippet = `\n![画像の説明](image:${up.name})\n`;
      const at = body.selectionStart ?? body.value.length;
      body.value = body.value.slice(0, at) + snippet + body.value.slice(at);
      draw();
      toast("画像を入れました（説明の文を書きかえてください）");
    } catch (e) { toast(e.message, true); }
  });
  const save = h("button", { class: "main", onclick: async () => {
    draw();
    const payload = { id: d.id || undefined, slug: d.slug, kind: d.kind };
    for (const [k] of LANGS) { payload["title_" + k] = d.title[k]; payload["body_" + k] = d.body[k]; }
    try { const r = await api("POST", "/api/posts", payload); blogEdit = r.post; toast("保存しました（公開と「サイトに反映」は一覧から）"); renderBlogEditor(el); } catch (e) { toast(e.message, true); }
  } }, "保存");
  el.append(h("div", { class: "sheet" },
    h("div", { class: "row" }, h("h2", { style: "margin:0" }, d.id ? `記事 #${d.id} を直す` : "新しい記事"), h("button", { class: "link", onclick: () => { blogEdit = null; show("blog"); } }, "← 一覧へ")),
    h("div", { class: "setting" }, h("div", {}, "種類"), kind, h("div", {})),
    h("div", { class: "setting" }, h("div", {}, "URL 名", h("div", { class: "help" }, "サイトの /ja/blog/<URL名>/ になる")), slug, h("div", {})),
    ltabs, title, body,
    h("div", { class: "row" }, h("label", {}, "画像を入れる ", file), save),
    h("p", { class: "muted" }, "見本（サイトでの見た目とは少しちがいます）"), preview));
}

// ---------------------------------------------------------------- バックアップ（要件#131）

async function loadBackups(el) {
  const r = await api("GET", "/api/backups");
  clear(el);
  const mb = (n) => (n / 1024 / 1024).toFixed(1) + " MB";
  const KIND = { manual: "手動", "before-restore": "戻す前の写し", "": "自動" };
  el.append(h("div", { class: "sheet" }, h("h2", {}, "バックアップ"),
    h("p", { class: "muted" }, `自動: ${r.enabled ? `${r.interval_hours} 時間ごと` : "取らない"}・残す数 ${r.keep}（変えるのは 設定 →「バックアップ」）。中身は DB（プレイヤー・対戦の記録・通報・お知らせ・記事・設定）、APIキー、管理画面のパスワード、画像。置き場所はこのマシンの server/var/backups だけなので、ときどき別のディスクにも写してください。`),
    h("div", { class: "row" }, h("button", { class: "main", onclick: async () => { try { await api("POST", "/api/backups"); toast("バックアップを取りました"); show("backup"); } catch (e) { toast(e.message, true); } } }, "今すぐ取る"))));
  const detail = h("div", {});
  const tbl = h("table", {}, h("tr", {}, h("th", {}, "日時"), h("th", {}, "種類"), h("th", {}, "プレイヤー"), h("th", {}, "大きさ"), h("th", {}, "")));
  for (const b of r.backups) {
    tbl.append(h("tr", {}, h("td", {}, fmtTime(b.created)), h("td", {}, KIND[b.note] ?? b.note), h("td", {}, fmtNum(b.players)), h("td", {}, mb(b.size)),
      h("td", {},
        h("button", { class: "link", onclick: () => playerRestore(detail, b) }, "プレイヤーだけ戻す"), " ",
        h("button", { class: "link", onclick: async () => {
          const typed = prompt(`サーバーのデータを、全部 ${fmtTime(b.created)} の時の状態に戻します。それより後のプレイヤー・対戦・設定の変更は消えます（戻す直前の写しは自動で取ります）。サーバーは再起動します（つながっている人は切れます）。\n\nよければ、このバックアップの名前「${b.id}」をそのまま入れてください。`);
          if (typed === null) return;
          try { await api("POST", `/api/backups/${b.id}/restore`, { confirm: typed.trim() }); toast("戻しています。サーバーが起動し直したら、もう一度ログインしてください"); } catch (e) { toast(e.message, true); }
        } }, "全部を戻す"), " ",
        h("button", { class: "link", onclick: async () => { if (confirm("このバックアップを消しますか？")) { try { await api("POST", `/api/backups/${b.id}/delete`, {}); show("backup"); } catch (e) { toast(e.message, true); } } } }, "消す"))));
  }
  el.append(h("div", { class: "sheet" }, r.backups.length ? tbl : h("p", { class: "muted" }, "まだバックアップはありません。")), detail);
}

function playerRestore(el, b) {
  clear(el);
  const q = h("input", { placeholder: "名前の一部か、プレイヤーの ID", style: "min-width:280px" });
  const list = h("div", {});
  const search = async () => {
    const r = await api("GET", `/api/backups/${b.id}/players?q=${encodeURIComponent(q.value.trim())}`);
    clear(list);
    if (!r.players.length) return list.append(h("p", { class: "muted" }, "見つかりません"));
    const t = h("table", {}, h("tr", {}, h("th", {}, "名前"), h("th", {}, "レート"), h("th", {}, "最後に来た日"), h("th", {}, "ID"), h("th", {}, "")));
    for (const p of r.players) t.append(h("tr", {}, h("td", {}, p.name), h("td", {}, p.rating), h("td", {}, fmtTime(p.last_seen)), h("td", { class: "muted" }, p.id),
      h("td", {}, h("button", { class: "act", onclick: async () => {
        if (!confirm(`「${p.name}」を ${fmtTime(b.created)} の時の状態（名前・レート・勝ち負け・称号・名札・見た目・利用停止など）に戻しますか？ ほかのプレイヤーには影響しません。`)) return;
        try { const out = await api("POST", `/api/backups/${b.id}/restore-player`, { player_id: p.id }); toast(`「${out.name}」を戻しました`); } catch (e) { toast(e.message, true); }
      } }, "このプレイヤーを戻す"))));
    list.append(t);
  };
  q.addEventListener("keydown", (e) => { if (e.key === "Enter") search(); });
  el.append(h("div", { class: "sheet" }, h("h2", {}, `プレイヤーだけ戻す（${fmtTime(b.created)} のバックアップから）`), h("div", { class: "row" }, q, h("button", { class: "act", onclick: search }, "探す")), list));
}

// ---------------------------------------------------------------- AI の指示文（要件#130）

async function loadPrompts(el) {
  const r = await api("GET", "/api/prompts");
  clear(el);
  const mode = h("select", {}, h("option", { value: "system" }, "プログラムの指示文を使う（既定）"), h("option", { value: "custom" }, "管理画面の指示文を使う"));
  mode.value = r.mode;
  const boxes = {};
  el.append(h("div", { class: "sheet" }, h("h2", {}, "AIの指示文"),
    h("p", { class: "muted" }, "AI に渡す指示文（システムプロンプト）を書きかえられます。「管理画面の指示文を使う」にすると、下で書いた指示文を使います（空の欄はプログラムの指示文のまま）。答えの形（JSON）はプログラムが決めるので、指示文を変えてもゲームが止まることはありませんが、採点の厳しさ・お客さんの作り方・不適切な発言の止め方が変わります。安全のための決まり（差別・個人情報を止める、発言の中の命令に従わない、など）は消さないでください。変えたら、何人か遊んで確かめてください。"),
    h("div", { class: "row" }, h("label", {}, "使う指示文 ", mode))));
  for (const it of r.items) {
    const ta = h("textarea", { style: "width:100%;min-height:220px;font-family:monospace;font-size:12px", placeholder: "（空ならプログラムの指示文）" });
    ta.value = it.custom;
    boxes[it.key] = ta;
    el.append(h("div", { class: "sheet" },
      h("div", { class: "row" }, h("h2", { style: "margin:0" }, it.label), h("span", { class: it.in_use === "custom" ? "warn" : "okc" }, it.in_use === "custom" ? "いま: 管理画面の指示文" : "いま: プログラムの指示文")),
      h("div", { class: "row" },
        h("button", { class: "act", onclick: () => { ta.value = it.default; } }, "プログラムの指示文を写して書きはじめる"),
        h("button", { class: "link", onclick: () => { if (confirm("この欄を空にします（プログラムの指示文に戻ります）。保存するまでは効きません。")) ta.value = ""; } }, "空にする（既定に戻す）")),
      ta,
      h("details", {}, h("summary", {}, "プログラムの指示文を見る"), h("pre", { style: "white-space:pre-wrap;font-size:12px" }, it.default))));
  }
  el.append(h("div", { class: "sheet" }, h("button", { class: "main", onclick: async () => {
    const texts = {};
    for (const [k, ta] of Object.entries(boxes)) texts[k] = ta.value;
    try { const out = await api("POST", "/api/prompts", { mode: mode.value, texts }); toast("保存しました（次の AI の呼び出しから効きます）"); loadPrompts(el); void out; } catch (e) { toast(e.message, true); }
  } }, "保存"), h("p", { class: "muted" }, "保存した内容は「操作の記録」に残ります（中身ではなく、どれを変えたか）。")));
}

// ---------------------------------------------------------------- AI の API の登録（要件#115）

let aiMode = "solo";

async function loadAi(el) {
  const r = await api("GET", "/api/ai-slots");
  renderAi(el, r);
}

function renderAi(el, r) {
  const provs = Object.fromEntries(r.providers.map((p) => [p.id, p]));
  const MODE = { solo: "1人用", versus: "対戦" };
  // 画面の上での並び（まだ保存していない変更を含む）。対戦が「1人用と同じ」なら対戦の並びは空
  const lists = { solo: r.solo.map((s) => ({ ...s, key: "", clear_key: false })), versus: r.versus.map((s) => ({ ...s, key: "", clear_key: false })) };
  let same = r.versus_same;
  const savedIds = new Set([...r.solo, ...r.versus].map((x) => x.id));
  const draw = () => {
    clear(el);
    const rows = lists[aiMode];
    const tabs = h("div", { class: "row ltabs" }, ...Object.entries(MODE).map(([k, l]) => h("button", { class: k === aiMode ? "on" : "", onclick: () => { aiMode = k; draw(); } }, l)));
    el.append(h("div", { class: "sheet" }, h("h2", {}, "AIのAPI（優先順位）"), tabs,
      h("p", { class: "muted" }, `1人用と対戦で、別々に最大 ${r.max} 個まで。上から順に使い、失敗したら次の順位へ切り替えます（全体で25秒まで。だめならキーワード判定・台本のお客さん）。` +
        "失敗した API は、連続10回目までは5分、そこからは1回ごとに5分ずつ延ばして最大60分のあいだ飛ばします。成功すると回数は0に戻ります。" +
        "キーはこのマシンの server/var/secrets.json にだけ保存し、ここには最初と最後の数文字しか出しません。"),
      r.saved ? null : h("p", { class: "warn" }, "まだこの画面で保存していません。いまは環境変数（ANTHROPIC_API_KEY など）から作った登録で動いています。保存すると、この画面の内容に切り替わります。")));
    if (aiMode === "versus") {
      const cb = h("input", { type: "checkbox" });
      cb.checked = same;
      cb.addEventListener("change", () => { same = cb.checked; draw(); });
      el.append(h("div", { class: "sheet" }, h("div", { class: "row" }, h("label", {}, cb, " 対戦も1人用と同じ並びを使う"),
        h("button", { class: "act", onclick: async () => {
          if (!confirm("1人用の並び（キーも）を対戦に写します。今の対戦の並びは置きかわります。よいですか？")) return;
          try { const out = await api("POST", "/api/ai-slots/copy", {}); toast("写しました"); renderAi(el, out); } catch (e) { toast(e.message, true); }
        } }, "1人用の並びを対戦に写す")),
        h("p", { class: "muted" }, "対戦は判定の回数が多いので、安くて速いモデルを上にしておくと料金と待ち時間が減ります。対戦の不適切な発言のチェックも、この並びを使います。")));
      if (same) { el.append(saveBar(rows)); return; }
    }
    rows.forEach((s, i) => {
      const prov = h("select", {}, ...r.providers.map((p) => h("option", { value: p.id }, p.label)));
      prov.value = s.provider;
      const dl = `dl-ai-${aiMode}-${i}`;
      const model = h("input", { value: s.model, list: dl, style: "width:100%", placeholder: "モデル名" });
      const gen = h("input", { value: s.gen_model || "", list: dl, style: "width:100%", placeholder: "空なら上と同じ" });
      const trans = h("input", { value: s.trans_model || "", list: dl, style: "width:100%", placeholder: "空なら上と同じ" });
      const limit = h("input", { type: "number", min: "0", step: "1", value: String(s.daily_limit || 0), style: "width:100%" });
      const memo = h("input", { value: s.label || "", maxlength: "40", style: "width:100%", placeholder: "例 予備のキー" });
      const longM = h("input", { value: s.long_model || "", list: dl, style: "width:100%", placeholder: "空なら切り替えない" });
      const tlim = h("input", { type: "number", min: "1000", step: "1000", value: String(s.token_limit || r.default_token_limit), style: "width:100%" });
      const url = h("input", { value: s.base_url, style: "width:100%", placeholder: "例 http://127.0.0.1:11434/v1" });
      const jm = h("select", {}, h("option", { value: "json_schema" }, "json_schema"), h("option", { value: "json_object" }, "json_object"));
      jm.value = s.json_mode;
      const key = h("input", { type: "password", autocomplete: "off", style: "width:100%", value: s.key,
        placeholder: s.key_set && !s.clear_key ? `設定済み（${s.key_mask}）。変えるときだけ入れる` : "APIキー" });
      const en = h("input", { type: "checkbox" });
      en.checked = s.enabled;
      prov.addEventListener("change", () => { s.provider = prov.value; if (!provs[s.provider].models.includes(s.model)) s.model = provs[s.provider].models[0] || ""; s.gen_model = ""; s.trans_model = ""; s.long_model = s.provider === "anthropic" ? r.default_long_model : ""; draw(); });
      model.addEventListener("input", () => (s.model = model.value));
      gen.addEventListener("input", () => (s.gen_model = gen.value));
      trans.addEventListener("input", () => (s.trans_model = trans.value));
      limit.addEventListener("input", () => (s.daily_limit = Number(limit.value || 0)));
      memo.addEventListener("input", () => (s.label = memo.value));
      longM.addEventListener("input", () => (s.long_model = longM.value));
      tlim.addEventListener("input", () => (s.token_limit = Number(tlim.value || 0)));
      url.addEventListener("input", () => (s.base_url = url.value));
      jm.addEventListener("change", () => (s.json_mode = jm.value));
      key.addEventListener("input", () => (s.key = key.value));
      en.addEventListener("change", () => (s.enabled = en.checked));
      const move = (d) => { const j = i + d; if (j < 0 || j >= rows.length) return; [rows[i], rows[j]] = [rows[j], rows[i]]; draw(); };
      const state = !s.enabled ? h("span", { class: "muted" }, "休止中")
        : s.skip_until ? h("span", { class: "warn" }, `失敗が続いているので ${fmtTime(s.skip_until)} まで飛ばす（連続 ${s.fails} 回）`)
        : s.daily_limit && s.used_today >= s.daily_limit ? h("span", { class: "warn" }, `今日の上限（${fmtNum(s.daily_limit)} 回）に達したので、明日まで飛ばす`)
        : s.fails ? h("span", { class: "warn" }, `連続 ${s.fails} 回失敗`) : h("span", { class: "okc" }, "使えます");
      const test = s.id && savedIds.has(s.id) ? h("button", { class: "act", onclick: async () => {
        try { const t = await api("POST", "/api/ai-slots/test", { id: s.id }); toast(t.message, !t.ok); renderAi(el, t); } catch (e) { toast(e.message, true); }
      } }, "この API を試す") : h("span", { class: "muted" }, "保存すると試せます");
      const field = (label, help, input, extra) => h("div", { class: "setting" }, h("div", {}, label, help ? h("div", { class: "help" }, help) : null), input, h("div", {}, extra || null));
      el.append(h("div", { class: "sheet" },
        h("div", { class: "row" }, h("h2", { style: "margin:0" }, `${MODE[aiMode]} ${i + 1}位`), s.label ? h("span", { class: "muted" }, s.label) : null,
          h("label", {}, en, " 使う"),
          h("button", { class: "link", onclick: () => move(-1), disabled: i === 0 }, "↑ 上げる"),
          h("button", { class: "link", onclick: () => move(1), disabled: i === rows.length - 1 }, "↓ 下げる"),
          h("button", { class: "link", onclick: () => { if (confirm(`${i + 1}位の登録を外しますか？（保存するまでは消えません）`)) { rows.splice(i, 1); draw(); } } }, "外す"),
          state),
        field("AIの種類", "", prov),
        field("モデル", "採点・お客さんの返事に使う。候補から選ぶか、手で入れる", h("div", {}, model, h("datalist", { id: dl }, ...provs[s.provider].models.map((m) => h("option", { value: m }))))),
        field("お客さんづくりのモデル", "1人につき1回だけ呼ぶので、ここだけ賢いモデルにしてもよい", gen),
        field("翻訳のモデル（グローバルサーバー・対戦）", "翻訳モードの人に、相手の言葉を訳して送るときに使う。安くて速いモデルがおすすめ", trans),
        s.provider === "anthropic" ? field("送る量が多いときのモデル", "下の目安（入力トークン）を超えそうなら、このモデルに切り替える。目安の半分を超えそうなときだけ count_tokens（無料）で数える", longM) : null,
        s.provider === "anthropic" ? field("切り替えの目安（トークン）", `既定 ${fmtNum(r.default_token_limit)}`, tlim) : null,
        s.provider === "custom" ? field("API の場所", "OpenAI 互換の API（…/v1 まで）", url) : null,
        s.provider === "custom" ? field("JSON の出させ方", "json_schema に対応していないAIは json_object", jm) : null,
        field("APIキー", s.provider === "custom" ? "キーが要らないもの（Ollama など）は空のまま" : "", key,
          s.key_set && !s.clear_key ? h("button", { class: "link", onclick: () => { s.clear_key = true; s.key = ""; draw(); } }, "キーを消す") : null),
        field("1日の上限", `0 = 上限なし。超えたらその日は次の順位へ（料金の使いすぎを防ぐ）。今日 ${fmtNum(s.used_today || 0)} 回`, limit),
        field("メモ", "管理画面にだけ出す", memo),
        h("div", { class: "row" }, test)));
    });
    el.append(saveBar(rows));
  };
  const saveBar = (rows) => {
    const add = h("button", { class: "act", disabled: rows.length >= r.max || (aiMode === "versus" && same), onclick: () => {
      rows.push({ id: "", enabled: true, provider: "anthropic", model: provs.anthropic.models[0], gen_model: "", trans_model: "", daily_limit: 0, label: "", long_model: r.default_long_model, token_limit: r.default_token_limit, base_url: "", json_mode: "json_schema", key: "", key_set: false, clear_key: false, fails: 0, skip_until: 0, used_today: 0 });
      draw();
    } }, `API を足す（${rows.length} / ${r.max}）`);
    const save = h("button", { class: "main", onclick: async () => {
      const pack = (list) => list.map((s) => ({ id: s.id, enabled: s.enabled, provider: s.provider, model: s.model, gen_model: s.gen_model || "", trans_model: s.trans_model || "", daily_limit: s.daily_limit || 0, label: s.label || "", long_model: s.long_model || "", token_limit: s.token_limit || r.default_token_limit, base_url: s.base_url, json_mode: s.json_mode, key: s.key, clear_key: s.clear_key }));
      try {
        const out = await api("POST", "/api/ai-slots", { solo: pack(lists.solo), versus: same ? [] : pack(lists.versus), versus_same: same });
        toast("保存しました");
        renderAi(el, out);
      } catch (e) { toast(e.message, true); }
    } }, "1人用・対戦をまとめて保存");
    return h("div", { class: "sheet" }, h("div", { class: "row" }, add, save),
      h("p", { class: "muted" }, "並べかえ・追加・外す・キーの変更は、保存するまで効きません（1人用と対戦の両方を保存します）。保存すると、変えた API の失敗の回数は消えます。1日の回数はサーバーを再起動すると0に戻ります。"));
  };
  draw();
}

async function loadSettings(el) {
  const r = await api("GET", "/api/settings");
  const pending = new Map(); // key -> 入力の部品（まだ保存していない）
  const search = h("input", { placeholder: "設定を探す（名前・説明・キー）", value: settingsQuery, style: "min-width:320px" });
  const saveAll = h("button", { class: "main", disabled: true }, "変えた設定をまとめて保存（0）");
  const refreshCount = () => {
    saveAll.textContent = `変えた設定をまとめて保存（${pending.size}）`;
    saveAll.disabled = pending.size === 0;
  };
  const valueOf = (s, input) => (s.type === "bool" ? input.value === "true" : s.type === "number" ? Number(input.value) : input.value);
  saveAll.addEventListener("click", async () => {
    let ok = 0;
    for (const [key, item] of pending) {
      try { await api("POST", "/api/settings", { key, value: valueOf(item.s, item.input) }); ok++; } catch (e) { toast(`${item.s.label}: ${e.message}`, true); return; }
    }
    toast(`${ok} 件を保存しました`);
    show("settings");
  });
  const top = h("div", { class: "sheet" },
    h("div", { class: "row" }, search, saveAll),
    h("p", { class: "muted" }, "Enter でその設定だけ保存。黄色は、まだ保存していない設定。変えた値はすぐに効きます（「再起動が必要」を除く）。APIキーはこのマシンの server/var/secrets.json にだけ保存し、ここには最初と最後の数文字しか出しません。変えた記録は「操作の記録」から戻せます。"));
  clear(el).append(top);
  const rows = [];
  const groups = {};
  for (const s of r.settings) (groups[s.group] = groups[s.group] || []).push(s);
  for (const [g, list] of Object.entries(groups)) {
    const sheet = h("div", { class: "sheet" }, h("h2", {}, g));
    for (const s of list) {
      let input;
      if (s.type === "bool") input = h("select", {}, h("option", { value: "true" }, "オン"), h("option", { value: "false" }, "オフ"));
      else if (s.type === "enum") input = h("select", {}, ...s.options.map((o) => h("option", { value: o }, o)));
      else if (s.type === "text") input = h("textarea", {});
      else if (s.type === "secret") input = h("input", { type: "password", placeholder: s.is_set ? `設定済み（${s.value}）。変えるときだけ入れる` : "まだありません", autocomplete: "off", style: "width:100%" });
      else {
        input = h("input", { type: s.type === "number" ? "number" : "text", style: "width:100%", step: "any" });
        if (s.suggestions) {
          const id = "dl-" + s.key.replace(/\W/g, "");
          input.setAttribute("list", id);
          sheet.append(h("datalist", { id }, ...s.suggestions.map((o) => h("option", { value: o }))));
        }
      }
      const original = s.type === "secret" ? "" : s.type === "bool" ? String(s.value) : String(s.value ?? "");
      if (s.type !== "secret") input.value = original;
      const saveOne = async () => {
        try { await setSetting(s.key, valueOf(s, input)); pending.delete(s.key); show("settings"); } catch (e) { toast(e.message, true); }
      };
      const mark = () => {
        const changed = input.value !== original;
        input.style.background = changed ? "#fff2b8" : "";
        if (changed) pending.set(s.key, { s, input }); else pending.delete(s.key);
        refreshCount();
      };
      input.addEventListener("input", mark);
      input.addEventListener("change", mark);
      input.addEventListener("keydown", (e) => { if (e.key === "Enter" && !(s.type === "text" && e.shiftKey)) { e.preventDefault(); saveOne(); } });
      const extra = s.type === "secret" && s.is_set ? h("button", { class: "link", onclick: async () => { if (confirm("このキーを消しますか？")) { await setSetting(s.key, ""); show("settings"); } } }, "消す") : null;
      const row = h("div", { class: "setting" },
        h("div", {}, h("div", {}, s.label, h("span", { class: "muted", style: "font-size:11px;margin-left:6px" }, s.key)), h("div", { class: "help" }, s.help), s.restart ? h("div", { class: "restart" }, "再起動が必要") : null),
        input, h("div", {}, h("button", { class: "act", onclick: saveOne }, "保存"), extra));
      row.dataset.find = `${s.label} ${s.help} ${s.key} ${g}`.toLowerCase();
      rows.push({ row, sheet });
      sheet.append(row);
    }
    el.append(sheet);
  }
  const filter = () => {
    settingsQuery = search.value;
    const q = search.value.trim().toLowerCase();
    for (const { row } of rows) row.style.display = q === "" || row.dataset.find.includes(q) ? "" : "none";
    for (const sheet of new Set(rows.map((x) => x.sheet))) {
      sheet.style.display = [...sheet.querySelectorAll(".setting")].some((x) => x.style.display !== "none") ? "" : "none";
    }
  };
  search.addEventListener("input", filter);
  filter();
  search.focus();
}

// ---------------------------------------------------------------- 操作の記録

async function loadAudit(el) {
  const r = await api("GET", "/api/audit");
  clear(el).append(h("div", { class: "sheet" }, h("h2", {}, "操作の記録（新しい200件）"),
    h("table", {}, h("tr", {}, ...["日時", "操作", "内容", ""].map((t) => h("th", {}, t))),
      r.logs.map((x) => h("tr", {}, h("td", {}, fmtTime(x.at)), h("td", {}, x.action), h("td", {}, x.detail),
        h("td", {}, x.action === "setting" && x.before_value ? h("button", { class: "act", onclick: async () => {
          if (!confirm("この変更の前の値に戻しますか？")) return;
          await api("POST", "/api/revert", { log_id: x.id }); toast("戻しました"); show("audit");
        } }, "前に戻す") : ""))))));
}

// ---------------------------------------------------------------- パスワード

async function loadAccount(el) {
  const cur = h("input", { type: "password", autocomplete: "current-password", placeholder: "今のパスワード" });
  const nw = h("input", { type: "password", autocomplete: "new-password", placeholder: "新しいパスワード（12文字以上）" });
  clear(el).append(h("div", { class: "sheet" }, h("h2", {}, "管理画面のパスワード"),
    h("p", { class: "muted" }, "変えると、最初のパスワードのファイル（admin_initial_password.txt）は消えます。忘れたときは、サーバーで server/var/admin_auth.json を消して再起動すると、新しい最初のパスワードが作られます。"),
    h("div", { class: "row" }, cur), h("div", { class: "row" }, nw),
    h("button", { class: "main", onclick: async () => { await api("POST", "/api/password", { current: cur.value, new_password: nw.value }); toast("変えました"); cur.value = ""; nw.value = ""; } }, "変える")));
}

const LOAD = { status: loadStatus, reports: loadReports, players: loadPlayers, matches: loadMatches, usage: loadUsage, notice: loadNotice, blog: loadBlog, ai: loadAi, prompts: loadPrompts, backup: loadBackups, settings: loadSettings, audit: loadAudit, account: loadAccount };

// ---------------------------------------------------------------- ログイン

function showLogin() {
  document.getElementById("app").style.display = "none";
  document.getElementById("login").style.display = "block";
  document.getElementById("pw").focus();
}

async function login() {
  try {
    const r = await api("POST", "/api/login", { password: document.getElementById("pw").value });
    CSRF = r.csrf;
    document.getElementById("pw").value = "";
    start();
  } catch (e) {
    toast(e.message, true);
  }
}

function start() {
  document.getElementById("login").style.display = "none";
  document.getElementById("app").style.display = "block";
  show("status");
}

document.getElementById("loginBtn").addEventListener("click", login);
document.getElementById("pw").addEventListener("keydown", (e) => { if (e.key === "Enter") login(); });
document.getElementById("logout").addEventListener("click", async () => { await api("POST", "/api/logout").catch(() => {}); CSRF = ""; showLogin(); });

(async () => {
  try {
    const r = await api("GET", "/api/session");
    CSRF = r.csrf;
    start();
  } catch {
    showLogin();
  }
})();
