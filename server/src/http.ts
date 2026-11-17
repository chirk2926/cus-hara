// HTTP の API（1人用・アカウント・ランキングなど）。対戦は ws.ts（WebSocket）。
import http from "node:http";
import crypto from "node:crypto";
import { config } from "./config.ts";
import { type Player, cleanName, createPlayer, playerByToken, renamePlayer, leaderboard } from "./db.ts";
import { publicPlayer } from "./protocol.ts";
import { type Customer, isStage, randomCustomer, publicCustomer, type StageId } from "./scenarios.ts";
import { judgeStaff } from "./keyword_judge.ts";
import { llmEnabled, generateCustomer, judgeStaffTurn, LlmError, type HistoryEntry } from "./llm.ts";
import { sttEnabled } from "./stt.ts";
import { allow } from "./ratelimit.ts";
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
}

const soloSessions = new Map<string, SoloSession>();
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
    return { players: leaderboard(clamp(Number(url.searchParams.get("limit") ?? 50), 1, 100)) };
  }

  // ここから下はログインが必要
  const player = authPlayer(req.headers.authorization);

  if (method === "GET" && p === "/api/v1/me") return { player: publicPlayer(player) };

  if (method === "POST" && p === "/api/v1/me") {
    const body = await readJson(req);
    const name = cleanName(body.name);
    renamePlayer(player.id, name);
    return { player: publicPlayer({ ...player, name }) };
  }

  if (method === "POST" && p === "/api/v1/solo/start") {
    const body = await readJson(req);
    if (!isStage(body.stage)) throw new HttpError(400, "bad_stage", "ステージの指定が正しくありません");
    const lang = toLang(body.lang);
    const avoid = Array.isArray(body.avoid) ? body.avoid.filter((x): x is string => typeof x === "string").slice(0, 10) : [];
    let customer: Customer | null = null;
    let source: "ai" | "script" = "script";
    let notice = "";
    if (llmEnabled()) {
      if (allow(`llm:${player.id}`, config.llmPerMinute, 60_000)) {
        try {
          customer = await generateCustomer(body.stage, avoid, lang);
          source = "ai";
        } catch (e) {
          notice = e instanceof LlmError ? `${e.message}。台本のお客さんで続けます` : "AIでお客さんを作れなかったので、台本のお客さんで続けます";
          log("solo generate failed", String(e));
        }
      } else {
        notice = "AIの利用回数の上限に達したので、しばらく台本のお客さんになります";
      }
    }
    if (customer === null) customer = randomCustomer(body.stage, avoid, lang);
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
    };
    soloSessions.set(session.id, session);
    return { session_id: session.id, source, notice, customer: publicCustomer(customer) };
  }

  if (method === "POST" && p === "/api/v1/solo/turn") {
    const body = await readJson(req);
    const s = typeof body.session_id === "string" ? soloSessions.get(body.session_id) : undefined;
    if (!s || s.playerId !== player.id) throw new HttpError(404, "no_session", "このお客さんとの会話は終わっています。次のお客さんへ進んでください");
    const reply = typeof body.reply === "string" ? body.reply.replace(/[\u0000-\u001f]/g, " ").trim().slice(0, 200) : "";
    if (reply === "") throw new HttpError(400, "empty_reply", "返事が空です");
    const anger = clamp(num(body.anger, 50), 0, 100);
    const resolve = clamp(num(body.resolve, 0), 0, 100);
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
    return { ...result, judged_by: judgedBy, notice };
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
