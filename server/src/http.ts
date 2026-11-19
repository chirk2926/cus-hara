// HTTP の API（1人用・アカウント・ランキングなど）。対戦は ws.ts（WebSocket）。
import http from "node:http";
import crypto from "node:crypto";
import { config } from "./config.ts";
import { sanctionOf, isActiveBan, setSanction, announcements, VS_CONSENT_VERSION, consentOf, setConsent, hasConsent, deletePlayer } from "./db.ts";
import { type Player, cleanName, cleanTitle, cleanTag, setPlayerTag, cleanAvatar, setPlayerAvatar, addReport, playerById, REPORT_REASONS, type ReportReason, createPlayer, playerByToken, renamePlayer, setPlayerTitle, leaderboard } from "./db.ts";
import { publicPlayer } from "./protocol.ts";
import { type Customer, isStage, randomCustomer, publicCustomer, type StageId, clampPayout, materializeSpend, spendWeight } from "./scenarios.ts";
import { judgeStaff } from "./keyword_judge.ts";
import { moderate } from "./moderation.ts";
import { runtime } from "./settings.ts";
import { markReported } from "./matchlogs.ts";
import { readNoticeImage } from "./notices.ts";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { llmEnabled, llmName, cacheStats, generateCustomer, judgeStaffTurn, LlmError, type HistoryEntry } from "./llm.ts";
import { sttEnabled } from "./stt.ts";
import { allow } from "./ratelimit.ts";
import { isAllowed, judgeAction, actionAsStaffLine } from "./actions.ts";
import { type Lang, toLang, LANGS } from "./lang.ts";
import type { Lobby } from "./lobby.ts";
import { log } from "./log.ts";

export const VERSION = "0.2.0";
const MAX_BODY = 64 * 1024;

/** 名前に不適切な言葉がないか（キーワード → AI が使えるときは AI も。要件#94） */
async function nameAllowed(name: string, key: string): Promise<boolean> {
  if (name === cleanName("")) return true;
  return !(await moderate(name, `name:${key}`)).flagged;
}

class HttpError extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

interface SoloSession {
  id: string;
  lang: Lang;
  playerId: string;
  stage: StageId;
  customer: Customer;
  source: "ai" | "script";
  history: HistoryEntry[];
  used: string[];
  updated: number;
  /** サーバーが覚えている怒りと納得（チート対策: クライアントが送る値はこれで検証する） */
  anger: number;
  resolve: number;
  /** 最後にサーバーが返事をした時刻（怒りは時間とともにしか上がらない） */
  lastAt: number;
  finished: boolean;
  hinted?: boolean;
}

const soloSessions = new Map<string, SoloSession>();

/** 判定のあとの怒り・納得をセッションに覚える。決着したら以後の入力は受け付けない */
function settle(s: SoloSession, anger: number, r: { anger_delta: number; resolve_delta: number; yielded: boolean }): void {
  s.anger = Math.min(100, Math.max(0, anger + r.anger_delta));
  s.resolve = Math.min(100, Math.max(0, s.resolve + r.resolve_delta));
  s.lastAt = Date.now();
  if (r.yielded || s.anger >= 100 || s.resolve >= 100) s.finished = true;
}
setInterval(() => {
  const now = Date.now();
  for (const [id, s] of soloSessions) if (now - s.updated > 30 * 60_000) soloSessions.delete(id);
}, 60_000).unref();

function clientIp(req: http.IncomingMessage): string {
  return requestIp(req);
}

/**
 * プレイヤーの本当の IP。前段のプロキシ（Cloudflare Tunnel など）を信じる設定（TRUST_PROXY=1）のときは、
 * Cloudflare の CF-Connecting-IP、なければ X-Forwarded-For の先頭を使う（要件#100: Cloudflare Tunnel では、
 * どのプレイヤーの接続も cloudflared（127.0.0.1）から来るため）
 */
export function requestIp(req: http.IncomingMessage): string {
  if (process.env.TRUST_PROXY === "1") {
    const cf = req.headers["cf-connecting-ip"];
    if (typeof cf === "string" && cf !== "") return cf.trim();
    const fwd = req.headers["x-forwarded-for"];
    if (typeof fwd === "string" && fwd !== "") return fwd.split(",")[0].trim();
  }
  return req.socket.remoteAddress ?? "unknown";
}

async function readJson(req: http.IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > MAX_BODY) throw new HttpError(413, "too_large", "送信データが大きすぎます");
    chunks.push(chunk as Buffer);
  }
  if (size === 0) return {};
  try {
    const v = JSON.parse(Buffer.concat(chunks).toString("utf-8"));
    return typeof v === "object" && v !== null ? (v as Record<string, unknown>) : {};
  } catch {
    throw new HttpError(400, "bad_json", "送信データの形式（JSON）が正しくありません");
  }
}

export function authPlayer(header: string | undefined): Player {
  const m = /^Bearer (.+)$/.exec(header ?? "");
  const p = m ? playerByToken(m[1]) : null;
  if (!p) throw new HttpError(401, "unauthorized", "ログイン情報が無効です。ゲームを再起動してください");
  // 利用停止（要件#100）
  const b = banMessage(p.id);
  if (b) throw new HttpError(403, "banned", b);
  return p;
}

/** 利用停止中なら、ゲームに出す説明（日本語。ゲームは code で訳す）。止められていなければ null */
export function banMessage(id: string): string | null {
  const s = sanctionOf(id);
  if (!isActiveBan(s.bannedUntil)) return null;
  const until = s.bannedUntil === -1 ? "無期限" : new Date(s.bannedUntil).toISOString().replace("T", " ").slice(0, 16) + " (UTC) まで";
  return `このアカウントは利用停止中です（${until}）。理由: ${s.reason || "利用規約に反する行為"}`;
}

/** 対戦を始められないとき（メンテナンス中・対戦の利用停止）の [code, 説明]。始められるなら null */
export function versusBlock(id: string): [string, string] | null {
  // 対戦の発言の取り扱いに同意していない人は、対戦できない（要件#101。1人用は遊べる）
  if (!hasConsent(id)) return ["consent_required", "対戦の前に、発言の取り扱いへの同意が必要です"];
  if (runtime.maintenance) return ["maintenance", runtime.maintenanceMessage || "メンテナンス中のため、対戦はお休みしています。1人用は遊べます"];
  const s = sanctionOf(id);
  if (isActiveBan(s.versusBannedUntil)) {
    const until = s.versusBannedUntil === -1 ? "無期限" : new Date(s.versusBannedUntil).toISOString().replace("T", " ").slice(0, 16) + " (UTC) まで";
    return ["versus_banned", `対戦の利用を停止しています（${until}）。理由: ${s.reason || "利用規約に反する行為"}`];
  }
  return null;
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const num = (v: unknown, def: number) => (typeof v === "number" && Number.isFinite(v) ? v : def);

export function info(lobby: Lobby) {
  return {
    name: "cushara-server",
    version: VERSION,
    ai: llmEnabled(),
    ai_provider: llmEnabled() ? llmName().split(":")[0] : "none",
    // プロンプトのキャッシュの効き（要件#78）: 読めた割合が高いほど料金が下がっている
    ai_cache: { calls: cacheStats.calls, cache_read_ratio: cacheStats.input + cacheStats.cacheRead > 0 ? Math.round((100 * cacheStats.cacheRead) / (cacheStats.input + cacheStats.cacheRead)) / 100 : 0 },
    voice: sttEnabled(),
    langs: LANGS,
    rules: { rounds: config.versus.rounds, opening_seconds: config.versus.openingSec, customer_seconds: config.versus.customerSec },
    online: lobby.stats(),
    // お知らせとメンテナンス（要件#100。管理画面から）
    maintenance: runtime.maintenance,
    maintenance_message: runtime.maintenance ? runtime.maintenanceMessage : "",
    // 言語ごとの見出しと本文（Markdown）。その言語が空なら英語 → 日本語の順で使う
    notices: announcements(true).slice(0, 5).map((a) => ({
      id: a.id,
      title: { ja: a.title_ja, en: a.title_en || a.title_ja, zh: a.title_zh || a.title_en || a.title_ja },
      body: { ja: a.text_ja, en: a.text_en || a.text_ja, zh: a.text_zh || a.text_en || a.text_ja },
      font: a.font,
      image: a.image ? `/api/v1/notice_image/${a.image}` : "",
      at: a.created_at,
    })),
  };
}

async function route(req: http.IncomingMessage, url: URL, lobby: Lobby): Promise<unknown> {
  const method = req.method ?? "GET";
  const p = url.pathname;

  if (method === "GET" && p === "/healthz") return { ok: true };
  if (method === "GET" && p === "/api/v1/info") return info(lobby);

  if (method === "POST" && p === "/api/v1/guest") {
    if (!allow(`guest:${clientIp(req)}`, config.guestsPerHour, 3_600_000)) {
      throw new HttpError(429, "rate_limited", "短い時間にアカウントを作りすぎています。1時間ほど待ってください");
    }
    const body = await readJson(req);
    // 不適切な名前は既定の名前にする（要件#94。作るときは止めずに進める）
    const { player, token } = createPlayer(await nameAllowed(cleanName(body.name), clientIp(req)) ? cleanName(body.name) : cleanName(""));
    log("new guest", player.name);
    return { token, player: publicPlayer(player) };
  }

  if (method === "GET" && p === "/api/v1/leaderboard") {
    return { players: leaderboard(clamp(Number.isFinite(Number(url.searchParams.get("limit") ?? 50)) ? Math.floor(Number(url.searchParams.get("limit") ?? 50)) : 50, 1, 100)) };
  }

  // ここから下はログインが必要
  const player = authPlayer(req.headers.authorization);

  if (method === "GET" && p === "/api/v1/me") {
    // 運営からの警告（要件#100）。ゲームが表示したら ack を送る
    const w = sanctionOf(player.id).warnMessage;
    return { player: publicPlayer(player), warning: w, vs_consent: consentOf(player.id).version, vs_consent_required: VS_CONSENT_VERSION };
  }

  // 退職（要件#101）: サーバーのアカウントとデータを消す
  if (method === "POST" && p === "/api/v1/me/delete") {
    deletePlayer(player.id);
    log("account deleted", player.id);
    return { ok: true };
  }

  // 対戦の発言の取り扱いへの同意（要件#101）。agree: true で今の版に同意、false で取り消す
  if (method === "POST" && p === "/api/v1/me/consent") {
    const body = await readJson(req);
    const agree = body.agree === true && Number(body.version) === VS_CONSENT_VERSION;
    if (body.agree === true && !agree) throw new HttpError(409, "consent_outdated", "同意の文が新しくなっています。ゲームを最新にしてください");
    setConsent(player.id, agree ? VS_CONSENT_VERSION : 0);
    log("consent", player.id, agree ? `agree v${VS_CONSENT_VERSION}` : "withdraw");
    return { ok: true, consent: consentOf(player.id), required: VS_CONSENT_VERSION };
  }

  if (method === "POST" && p === "/api/v1/me/ack_warning") {
    setSanction(player.id, { warnMessage: "" });
    return { ok: true };
  }

  if (method === "POST" && p === "/api/v1/me") {
    const body = await readJson(req);
    // 送られてきた項目だけ変える（名前だけ・称号だけでもよい）
    let next: Player = { ...player };
    if (body.name !== undefined) {
      next.name = cleanName(body.name);
      // 名前は対戦の相手やランキングに出るので、不適切な名前は断る（要件#94）
      if (!(await nameAllowed(next.name, player.id))) throw new HttpError(400, "name_not_allowed", "その名前は使えません");
      renamePlayer(player.id, next.name);
    }
    if (body.title !== undefined) {
      next = { ...next, title: cleanTitle(body.title) };
      setPlayerTitle(player.id, next.title ?? "");
    }
    if (body.tag !== undefined) {
      next = { ...next, tag: cleanTag(body.tag) };
      setPlayerTag(player.id, next.tag ?? "");
    }
    if (body.avatar !== undefined) {
      next = { ...next, avatar: cleanAvatar(body.avatar) };
      setPlayerAvatar(player.id, next.avatar ?? "");
    }
    return { player: publicPlayer(next) };
  }

  // プレイヤーの通報（要件#87）。ブロックの機能はない。運営が reports テーブルで確かめる
  if (method === "POST" && p === "/api/v1/report") {
    const body = await readJson(req);
    const target = typeof body.player_id === "string" ? body.player_id : "";
    const reason = typeof body.reason === "string" && (REPORT_REASONS as readonly string[]).includes(body.reason) ? (body.reason as ReportReason) : null;
    if (reason === null) throw new HttpError(400, "bad_reason", "通報の理由を選んでください");
    if (target === "" || target === player.id || playerById(target) === null) throw new HttpError(400, "bad_target", "通報する相手が見つかりません");
    if (!allow(`report:${player.id}`, 10, 3_600_000)) throw new HttpError(429, "too_many_reports", "通報が多すぎます。しばらくしてからにしてください");
    const matchId = typeof body.match_id === "string" ? body.match_id.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 64) : "";
    const note = typeof body.note === "string" ? body.note.replace(/[\u0000-\u001f\u007f<>]/g, " ").trim().slice(0, 200) : "";
    const saved = addReport(player.id, target, matchId, reason, note);
    if (saved && matchId !== "") markReported(matchId);
    log("report", player.id, "->", target, reason, saved ? "saved" : "duplicate");
    return { ok: true, saved };
  }

  if (method === "POST" && p === "/api/v1/solo/start") {
    const body = await readJson(req);
    if (!isStage(body.stage)) throw new HttpError(400, "bad_stage", "ステージの指定が正しくありません");
    const lang = toLang(body.lang);
    // AIへの指示文に入るので、長さと文字を絞る（要件#77: 長い文や指示を混ぜられないように）
    const avoid = Array.isArray(body.avoid)
      ? body.avoid.filter((x): x is string => typeof x === "string").slice(0, 10).map((x) => x.replace(/[\u0000-\u001f\n\r]/g, " ").trim().slice(0, 30)).filter(Boolean)
      : [];
    const wild = body.event === "wild";
    // クレーンのペイアウト率（要件#55）。ゲームセンターの「取れない」クレームの出やすさと、言う金額が変わる
    const payout = clampPayout(body.payout);
    // AIのお客さんを「〇〇円使っても取れない」にする確率: 30% で 0.3。低いほど多い
    const spendAi = body.stage === "arcade" && !wild && Math.random() < Math.min(0.8, 0.3 * spendWeight(payout));
    let customer: Customer | null = null;
    let source: "ai" | "script" = "script";
    let notice = "";
    if (llmEnabled()) {
      if (allow(`llm:${player.id}`, config.llmPerMinute, 60_000)) {
        try {
          customer = materializeSpend(await generateCustomer(body.stage, avoid, lang, wild, spendAi), payout, lang);
          source = "ai";
        } catch (e) {
          notice = e instanceof LlmError ? `${e.message}。台本のお客さんで続けます` : "AIでお客さんを作れなかったので、台本のお客さんで続けます";
          log("solo generate failed", String(e));
        }
      } else {
        notice = "AIの利用回数の上限に達したので、しばらく台本のお客さんになります";
      }
    }
    if (customer === null) customer = randomCustomer(body.stage, avoid, lang, wild, payout);
    if (wild) customer.rare = true;
    // 1人のプレイヤーが同時に持てるセッションは3つまで
    const mine = [...soloSessions.values()].filter((s) => s.playerId === player.id).sort((a, b) => a.updated - b.updated);
    while (mine.length >= 3) soloSessions.delete(mine.shift()!.id);
    const session: SoloSession = {
      id: crypto.randomUUID(),
      lang,
      playerId: player.id,
      stage: body.stage,
      customer,
      source,
      history: [{ role: "customer", text: customer.opening }],
      used: [],
      updated: Date.now(),
      anger: customer.start_anger,
      resolve: 0,
      lastAt: Date.now(),
      finished: false,
    };
    // 全体の上限（メモリを使いきらないように。古いものから捨てる。要件#77）
    if (soloSessions.size >= 20000) {
      const oldest = [...soloSessions.values()].sort((a, b) => a.updated - b.updated).slice(0, 1000);
      for (const o of oldest) soloSessions.delete(o.id);
    }
    soloSessions.set(session.id, session);
    return { session_id: session.id, source, notice, event: wild ? "wild" : "", customer: publicCustomer(customer) };
  }

  // 店長のアドバイス（要件#52）: 正しい方向の言葉を1つと、効く行動ボタンを1つ教える。1人のお客さんにつき1回だけ
  if (method === "POST" && p === "/api/v1/solo/hint") {
    const body = await readJson(req);
    const s = soloSessions.get(String(body.session_id ?? ""));
    if (!s || s.playerId !== player.id) throw new HttpError(404, "no_session", "会話が見つかりません");
    if (s.finished) throw new HttpError(409, "finished", "このお客さんとの会話は終わっています");
    if (s.hinted) throw new HttpError(409, "hinted", "店長のアドバイスはもう聞きました");
    s.hinted = true;
    const words = s.customer.solution_keywords ?? [];
    const keyword = words.length > 0 ? words[Math.floor(Math.random() * words.length)] : "";
    const good = Object.entries(s.customer.actions ?? {}).filter(([id, v]) => v === "good" && isAllowed(s.stage, s.customer, id)).map(([id]) => id);
    return { keyword, action: good[0] ?? "" };
  }

  if (method === "POST" && p === "/api/v1/solo/turn") {
    const body = await readJson(req);
    const s = typeof body.session_id === "string" ? soloSessions.get(body.session_id) : undefined;
    if (!s || s.playerId !== player.id) throw new HttpError(404, "no_session", "このお客さんとの会話は終わっています。次のお客さんへ進んでください");
    if (s.finished) throw new HttpError(409, "finished", "このお客さんとの会話は終わっています");
    if (s.history.filter((h) => h.role === "staff").length >= config.soloMaxTurns) {
      s.finished = true;
      throw new HttpError(409, "too_long", "やりとりが長すぎるので、このお客さんは帰りました");
    }
    // チート対策（要件#47）: 納得はサーバーの値だけを使う。怒りは、待っている間に上がる分だけ
    // クライアントの値を受け入れる（サーバーが覚えている値より下げることはできない）
    const resolve = s.resolve;
    const anger = Math.max(s.anger, clamp(num(body.anger, s.anger), 0, 100));
    // 店の行動ボタン（要件#34, #37）: 点数は表どおり。AIがあればお客さんの反応のセリフだけAIに作らせる
    if (typeof body.action === "string" && body.action !== "") {
      const id = body.action;
      if (!isAllowed(s.stage, s.customer, id)) throw new HttpError(400, "bad_action", "この場面では使えない行動です");
      const fixed = judgeAction(s.customer, id, anger, resolve, s.lang);
      s.history.push({ role: "staff", text: actionAsStaffLine(id, s.lang) });
      let line = fixed.customer_reply;
      let judgedBy: "ai" | "keyword" = "keyword";
      if (s.source === "ai" && allow(`llm:${player.id}`, config.llmPerMinute, 60_000)) {
        try {
          const ai = await judgeStaffTurn(s.stage, s.customer, s.history, anger, resolve, false, s.lang);
          line = ai.customer_reply;
          judgedBy = "ai";
        } catch {
          // 台本のセリフのまま
        }
      }
      s.history.push({ role: "customer", text: line });
      s.updated = Date.now();
      settle(s, anger, fixed);
      return { ...fixed, customer_reply: line, judged_by: judgedBy, notice: "", action: id, anger: s.anger, resolve: s.resolve };
    }
    const reply = typeof body.reply === "string" ? body.reply.replace(/[\u0000-\u001f]/g, " ").trim().slice(0, 256) : "";
    if (reply === "") throw new HttpError(400, "empty_reply", "返事が空です");
    s.history.push({ role: "staff", text: reply });
    let result = null;
    let judgedBy: "ai" | "keyword" = "keyword";
    let notice = "";
    if (s.source === "ai") {
      if (allow(`llm:${player.id}`, config.llmPerMinute, 60_000)) {
        try {
          result = await judgeStaffTurn(s.stage, s.customer, s.history, anger, resolve, false, s.lang);
          judgedBy = "ai";
        } catch (e) {
          notice = e instanceof LlmError ? `${e.message}（簡易判定）` : "AIの判定に失敗したので簡易判定にしました";
        }
      } else {
        notice = "AIの利用回数の上限に達したので簡易判定にしました";
      }
    }
    if (result === null) result = judgeStaff(s.customer, reply, s.used, anger, resolve, s.lang);
    s.used.push(reply);
    s.history.push({ role: "customer", text: result.customer_reply });
    s.updated = Date.now();
    settle(s, anger, result);
    return { ...result, judged_by: judgedBy, notice, anger: s.anger, resolve: s.resolve };
  }

  throw new HttpError(404, "not_found", "そのAPIはありません");
}

export function createHttpServer(lobby: Lobby): http.Server {
  return http.createServer((req, res) => {
    const url = new URL(req.url ?? "/", "http://localhost");
    // プライバシーポリシー（要件#101）。/privacy?lang=ja|en|zh
    if (req.method === "GET" && (url.pathname === "/privacy" || url.pathname === "/privacy/")) {
      const lang = ["ja", "en", "zh"].includes(url.searchParams.get("lang") ?? "") ? url.searchParams.get("lang") : "ja";
      try {
        const html = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "public", `privacy.${lang}.html`), "utf-8");
        res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=3600", "x-content-type-options": "nosniff",
          "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'" });
        res.end(html);
      } catch {
        res.writeHead(404, { "content-type": "text/plain" });
        res.end("not found");
      }
      return;
    }
    // お知らせの画像（要件#100）。だれでも読める（名前は推測できない）
    const img = /^\/api\/v1\/notice_image\/([0-9a-f]{32}\.(?:png|jpg))$/.exec(url.pathname);
    if (req.method === "GET" && img) {
      const f = readNoticeImage(img[1]);
      if (!f) {
        res.writeHead(404, { "content-type": "text/plain" });
        res.end("not found");
        return;
      }
      res.writeHead(200, { "content-type": f.type, "cache-control": "public, max-age=86400", "x-content-type-options": "nosniff", "content-length": String(f.bytes.length) });
      res.end(f.bytes);
      return;
    }
    route(req, url, lobby)
      .then((body) => {
        res.writeHead(200, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
        res.end(JSON.stringify(body));
      })
      .catch((e: unknown) => {
        const he = e instanceof HttpError ? e : new HttpError(500, "server_error", "サーバー内部のエラーです。しばらくしてからもう一度お試しください");
        if (!(e instanceof HttpError)) log("http error", req.method, url.pathname, e);
        res.writeHead(he.status, { "content-type": "application/json; charset=utf-8" });
        res.end(JSON.stringify({ error: { code: he.code, message: he.message } }));
      });
  });
}
