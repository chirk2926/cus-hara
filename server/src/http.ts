// HTTP の API（1人用・アカウント・ランキングなど）。対戦は ws.ts（WebSocket）。
import http from "node:http";
import crypto from "node:crypto";
import { config } from "./config.ts";
import { type Player, cleanName, cleanTitle, createPlayer, playerByToken, renamePlayer, setPlayerTitle, leaderboard } from "./db.ts";
import { publicPlayer } from "./protocol.ts";
import { type Customer, isStage, randomCustomer, publicCustomer, type StageId, clampPayout, materializeSpend, spendWeight } from "./scenarios.ts";
import { judgeStaff } from "./keyword_judge.ts";
import { llmEnabled, llmName, cacheStats, generateCustomer, judgeStaffTurn, LlmError, type HistoryEntry } from "./llm.ts";
import { sttEnabled } from "./stt.ts";
import { allow } from "./ratelimit.ts";
import { isAllowed, judgeAction, actionAsStaffLine } from "./actions.ts";
import { type Lang, toLang, LANGS } from "./lang.ts";
import type { Lobby } from "./lobby.ts";
import { log } from "./log.ts";

export const VERSION = "0.2.0";
const MAX_BODY = 64 * 1024;

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
  const fwd = req.headers["x-forwarded-for"];
  if (typeof fwd === "string" && process.env.TRUST_PROXY === "1") return fwd.split(",")[0].trim();
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
  return p;
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
    const { player, token } = createPlayer(cleanName(body.name));
    log("new guest", player.name);
    return { token, player: publicPlayer(player) };
  }

  if (method === "GET" && p === "/api/v1/leaderboard") {
    return { players: leaderboard(clamp(Number.isFinite(Number(url.searchParams.get("limit") ?? 50)) ? Math.floor(Number(url.searchParams.get("limit") ?? 50)) : 50, 1, 100)) };
  }

  // ここから下はログインが必要
  const player = authPlayer(req.headers.authorization);

  if (method === "GET" && p === "/api/v1/me") return { player: publicPlayer(player) };

  if (method === "POST" && p === "/api/v1/me") {
    const body = await readJson(req);
    // 送られてきた項目だけ変える（名前だけ・称号だけでもよい）
    let next: Player = { ...player };
    if (body.name !== undefined) {
      next.name = cleanName(body.name);
      renamePlayer(player.id, next.name);
    }
    if (body.title !== undefined) {
      next = { ...next, title: cleanTitle(body.title) };
      setPlayerTitle(player.id, next.title ?? "");
    }
    return { player: publicPlayer(next) };
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
    const reply = typeof body.reply === "string" ? body.reply.replace(/[\u0000-\u001f]/g, " ").trim().slice(0, 200) : "";
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
