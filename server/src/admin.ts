// 管理画面（要件#100）。サーバーの状態・通報・プレイヤー・設定（APIキー・AIモデル・LLMの種類・上限・対戦の時間など）を
// ブラウザで見て変える。
//
// 外から絶対につながらないようにするための決まり（docs/SERVER.md 11節）:
//   1. 127.0.0.1（このマシンの中）でだけ待ち受ける。設定でも変えられない
//   2. 届いた接続の相手が 127.0.0.1 / ::1 でなければ断る
//   3. プロキシを通ってきた印（CF-Connecting-IP・X-Forwarded-For など）があれば断る
//      （Cloudflare Tunnel をまちがえて管理画面に向けても、外の人は入れない）
//   4. Host がこのマシンの名前（localhost / 127.0.0.1）でなければ断る（DNS リバインディング対策）
//   5. パスワード（最初は自動で作って var/admin_initial_password.txt に書く）でログイン。
//      ログイン後は HttpOnly の Cookie。変更の操作は CSRF の印と Origin も確かめる
// 家の PC からは SSH のトンネルで開く（ssh -L 8790:127.0.0.1:8790 サーバー）。
import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { config } from "./config.ts";
import { log } from "./log.ts";
import {
  openDb, playerById, sanctionOf, setSanction, isActiveBan, renamePlayer, setPlayerTitle, cleanName, matchLog, aiUsage,
  announcements, addAnnouncement, setAnnouncementActive, deleteAnnouncement, adminLog, adminLogs, adminLogById,
} from "./db.ts";
import { listSettings, setSetting, SettingError, settingDef, currentValue, costUsd, runtime } from "./settings.ts";
import { llmEnabled, llmName, cacheStats, pingLlm } from "./llm.ts";
import { sttEnabled } from "./stt.ts";
import { kickPlayer, onlinePlayers } from "./ws.ts";
import { VERSION } from "./http.ts";
import type { Lobby } from "./lobby.ts";

const here = path.dirname(fileURLToPath(import.meta.url));
const PAGE = path.join(here, "..", "admin", "index.html");
const SCRIPT = path.join(here, "..", "admin", "app.js");
const LOOPBACK = new Set(["127.0.0.1", "::1", "::ffff:127.0.0.1"]);
const PROXY_HEADERS = ["cf-connecting-ip", "cf-ray", "cf-ipcountry", "x-forwarded-for", "x-forwarded-host", "x-real-ip", "forwarded", "true-client-ip"];
const SESSION_IDLE_MS = 2 * 3_600_000;
const startedAt = Date.now();

export const ADMIN_HOST = "127.0.0.1";

// ---------------------------------------------------------------- パスワード

function authFile(): string | null {
  if (process.env.ADMIN_AUTH_PATH) return process.env.ADMIN_AUTH_PATH;
  if (config.dbPath === ":memory:") return null;
  return path.join(path.dirname(config.dbPath), "admin_auth.json");
}

let memAuth: { salt: string; hash: string } | null = null;

function hashPw(pw: string, salt: string): string {
  return crypto.scryptSync(pw, salt, 32).toString("hex");
}

function loadAuth(): { salt: string; hash: string } {
  const f = authFile();
  if (f && fs.existsSync(f)) return JSON.parse(fs.readFileSync(f, "utf-8"));
  if (memAuth) return memAuth;
  // 初めて: 環境変数 ADMIN_PASSWORD があればそれ、なければ自動で作って、このマシンの中のファイルに書く
  const pw = process.env.ADMIN_PASSWORD || crypto.randomBytes(12).toString("base64url");
  const a = savePassword(pw);
  if (!process.env.ADMIN_PASSWORD && f) {
    const initial = path.join(path.dirname(f), "admin_initial_password.txt");
    fs.writeFileSync(initial, pw + "\n", { mode: 0o600 });
    log(`管理画面の最初のパスワードを ${initial} に書きました（ログインしたら変えてください）`);
  }
  return a;
}

function savePassword(pw: string): { salt: string; hash: string } {
  const salt = crypto.randomBytes(16).toString("hex");
  const a = { salt, hash: hashPw(pw, salt) };
  const f = authFile();
  if (f) {
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.writeFileSync(f, JSON.stringify(a), { mode: 0o600 });
    fs.chmodSync(f, 0o600);
  } else memAuth = a;
  return a;
}

function checkPassword(pw: string): boolean {
  const a = loadAuth();
  const h = Buffer.from(hashPw(pw, a.salt), "hex");
  const want = Buffer.from(a.hash, "hex");
  return h.length === want.length && crypto.timingSafeEqual(h, want);
}

// ---------------------------------------------------------------- ログインの状態

interface Session {
  csrf: string;
  last: number;
}

const sessions = new Map<string, Session>();
const loginFails: number[] = [];

function cookieOf(req: http.IncomingMessage): string {
  const m = /(?:^|;\s*)cushara_admin=([A-Za-z0-9_-]+)/.exec(req.headers.cookie ?? "");
  return m ? m[1] : "";
}

function sessionOf(req: http.IncomingMessage): Session | null {
  const id = cookieOf(req);
  const s = id ? sessions.get(id) : undefined;
  if (!s) return null;
  if (Date.now() - s.last > SESSION_IDLE_MS) {
    sessions.delete(id);
    return null;
  }
  s.last = Date.now();
  return s;
}

class AdminError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

// ---------------------------------------------------------------- 外からの接続を断る

/** 管理画面に来てよい接続か。だめなら理由 */
export function rejectReason(req: http.IncomingMessage, port: number): string | null {
  const remote = req.socket.remoteAddress ?? "";
  if (!LOOPBACK.has(remote)) return "remote";
  for (const h of PROXY_HEADERS) if (req.headers[h] !== undefined) return "proxied";
  const host = String(req.headers.host ?? "");
  const ok = [`127.0.0.1:${port}`, `localhost:${port}`, `[::1]:${port}`];
  if (!ok.includes(host.toLowerCase())) return "host";
  return null;
}

function originOk(req: http.IncomingMessage, port: number): boolean {
  const o = req.headers.origin;
  if (o === undefined) return true; // 同じページからの fetch では付かないこともある（CSRF の印で守る）
  return [`http://127.0.0.1:${port}`, `http://localhost:${port}`, `http://[::1]:${port}`].includes(String(o).toLowerCase());
}

// ---------------------------------------------------------------- 本体

export function createAdminServer(lobby: Lobby): http.Server {
  loadAuth();
  const server = http.createServer(async (req, res) => {
    const port = (server.address() as { port: number } | null)?.port ?? 0;
    const headers: Record<string, string> = {
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      "x-frame-options": "DENY",
      "referrer-policy": "no-referrer",
      "content-security-policy": "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
    };
    const send = (status: number, body: unknown, extra: Record<string, string> = {}) => {
      const isHtml = typeof body === "string";
      res.writeHead(status, { ...headers, "content-type": isHtml ? "text/html; charset=utf-8" : "application/json; charset=utf-8", ...extra });
      res.end(isHtml ? body : JSON.stringify(body));
    };
    const why = rejectReason(req, port);
    if (why) {
      log("admin: refused", why, req.socket.remoteAddress ?? "");
      res.writeHead(403, headers);
      res.end("forbidden");
      return;
    }
    try {
      const url = new URL(req.url ?? "/", `http://127.0.0.1:${port}`);
      const method = req.method ?? "GET";
      if (method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
        send(200, fs.readFileSync(PAGE, "utf-8"));
        return;
      }
      if (method === "GET" && url.pathname === "/app.js") {
        res.writeHead(200, { ...headers, "content-type": "text/javascript; charset=utf-8" });
        res.end(fs.readFileSync(SCRIPT, "utf-8"));
        return;
      }
      if (!url.pathname.startsWith("/api/")) throw new AdminError(404, "ありません");
      const body = method === "GET" ? {} : await readJson(req);
      // ログイン（パスワード）
      if (method === "POST" && url.pathname === "/api/login") {
        const now = Date.now();
        while (loginFails.length > 0 && now - loginFails[0] > 15 * 60_000) loginFails.shift();
        if (loginFails.length >= 10) throw new AdminError(429, "失敗が多すぎます。15分ほど待ってください");
        if (typeof body.password !== "string" || !checkPassword(body.password)) {
          loginFails.push(now);
          adminLog("login_failed", "", "");
          throw new AdminError(401, "パスワードがちがいます");
        }
        const id = crypto.randomBytes(32).toString("base64url");
        const s: Session = { csrf: crypto.randomBytes(24).toString("base64url"), last: now };
        sessions.set(id, s);
        adminLog("login", "", "");
        send(200, { ok: true, csrf: s.csrf }, { "set-cookie": `cushara_admin=${id}; HttpOnly; SameSite=Strict; Path=/` });
        return;
      }
      const s = sessionOf(req);
      if (!s) throw new AdminError(401, "ログインしてください");
      if (method !== "GET") {
        if (req.headers["x-admin-csrf"] !== s.csrf || !originOk(req, port)) throw new AdminError(403, "画面を読み込み直してください（CSRF）");
      }
      const out = await route(method, url, body, lobby, s);
      if (out === "__logout__") {
        sessions.delete(cookieOf(req));
        send(200, { ok: true }, { "set-cookie": "cushara_admin=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0" });
        return;
      }
      send(200, out);
    } catch (e) {
      if (e instanceof AdminError) send(e.status, { error: e.message });
      else if (e instanceof SettingError) send(400, { error: e.message });
      else {
        log("admin error", String(e));
        send(500, { error: "サーバーの中でエラーが起きました: " + String(e).slice(0, 200) });
      }
    }
  });
  return server;
}

async function readJson(req: http.IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const c of req) {
    size += (c as Buffer).length;
    if (size > 64 * 1024) throw new AdminError(413, "大きすぎます");
    chunks.push(c as Buffer);
  }
  if (size === 0) return {};
  try {
    const v = JSON.parse(Buffer.concat(chunks).toString("utf-8"));
    return typeof v === "object" && v !== null ? v : {};
  } catch {
    throw new AdminError(400, "JSON の形が正しくありません");
  }
}

const str = (v: unknown, n = 300) => (typeof v === "string" ? v.slice(0, n) : "");
const int = (v: unknown, d: number) => (typeof v === "number" && Number.isFinite(v) ? Math.floor(v) : d);

async function route(method: string, url: URL, body: Record<string, unknown>, lobby: Lobby, s: Session): Promise<unknown> {
  const p = url.pathname;
  const db = openDb();

  if (method === "GET" && p === "/api/session") return { csrf: s.csrf };
  if (method === "POST" && p === "/api/logout") return "__logout__";
  if (method === "POST" && p === "/api/password") {
    const pw = str(body.new_password, 200);
    if (pw.length < 12) throw new AdminError(400, "12文字以上にしてください");
    if (typeof body.current !== "string" || !checkPassword(body.current)) throw new AdminError(401, "今のパスワードがちがいます");
    savePassword(pw);
    const f = authFile();
    if (f) fs.rmSync(path.join(path.dirname(f), "admin_initial_password.txt"), { force: true });
    adminLog("password", "", "管理画面のパスワードを変えた");
    return { ok: true };
  }

  // ---- 状態
  if (method === "GET" && p === "/api/status") {
    const count = (sql: string, ...a: unknown[]) => Number((db.prepare(sql).get(...(a as never[])) as { n: number }).n);
    const dayStart = new Date();
    dayStart.setHours(0, 0, 0, 0);
    let dbSize = 0;
    try {
      dbSize = config.dbPath === ":memory:" ? 0 : fs.statSync(config.dbPath).size;
    } catch {
      dbSize = 0;
    }
    const mem = process.memoryUsage();
    return {
      version: VERSION,
      node: process.version,
      uptime_sec: Math.round((Date.now() - startedAt) / 1000),
      host: os.hostname(),
      load: os.loadavg(),
      memory_mb: Math.round(mem.rss / 1048576),
      db_size_mb: Math.round((dbSize / 1048576) * 10) / 10,
      maintenance: runtime.maintenance,
      online: { connected: onlinePlayers(), ...lobby.stats() },
      ai: { enabled: llmEnabled(), name: llmEnabled() ? llmName() : "none", calls: cacheStats.calls, input: cacheStats.input, output: cacheStats.output, cache_read: cacheStats.cacheRead },
      voice: sttEnabled() ? config.sttProvider : "none",
      players: { total: count("SELECT COUNT(*) AS n FROM players"), new_today: count("SELECT COUNT(*) AS n FROM players WHERE created_at >= ?", dayStart.getTime()), active_today: count("SELECT COUNT(*) AS n FROM players WHERE last_seen >= ?", dayStart.getTime()) },
      matches_today: count("SELECT COUNT(*) AS n FROM matches WHERE created_at >= ?", dayStart.getTime()),
      reports_open: count("SELECT COUNT(*) AS n FROM reports WHERE status = 'open'"),
      bans: count("SELECT COUNT(*) AS n FROM players WHERE banned_until = -1 OR banned_until > ? OR versus_banned_until = -1 OR versus_banned_until > ?", Date.now(), Date.now()),
      trust_proxy: process.env.TRUST_PROXY === "1",
    };
  }

  // ---- 設定
  if (method === "GET" && p === "/api/settings") return { settings: listSettings() };
  if (method === "POST" && p === "/api/settings") {
    const key = str(body.key, 100);
    const d = settingDef(key);
    if (!d) throw new AdminError(404, "その設定はありません");
    const raw = d.type === "secret" ? "" : JSON.stringify(currentValue(d));
    const r = setSetting(key, body.value);
    adminLog("setting", key, `${d.label}: ${r.before} → ${r.after}`, raw, d.type === "secret" ? "" : JSON.stringify(currentValue(d)));
    return { ok: true, restart: r.restart, settings: listSettings() };
  }
  if (method === "POST" && p === "/api/revert") {
    const e = adminLogById(int(body.log_id, -1));
    if (!e || e.action !== "setting") throw new AdminError(404, "戻せる記録ではありません");
    const d = settingDef(e.target);
    if (!d || d.type === "secret" || e.before_value === "") throw new AdminError(400, "APIキーなど秘密の値は戻せません（入れ直してください）");
    const r = setSetting(e.target, JSON.parse(e.before_value));
    adminLog("setting_revert", e.target, `${d.label}: ${r.before} → ${r.after}（記録 #${e.id} を戻した）`, "", "");
    return { ok: true, settings: listSettings() };
  }
  if (method === "POST" && p === "/api/test-ai") {
    if (!llmEnabled()) return { ok: false, message: "AIを使わない設定、または APIキーがありません" };
    try {
      await pingLlm();
      return { ok: true, message: `つながりました（${llmName()}）` };
    } catch (e) {
      return { ok: false, message: String(e instanceof Error ? e.message : e).slice(0, 300) };
    }
  }
  if (method === "POST" && p === "/api/restart") {
    adminLog("restart", "", "サーバーを再起動した");
    // systemd（Restart=always）が起動し直す（docs/HOME_SERVER.md）
    setTimeout(() => process.exit(0), 500).unref();
    return { ok: true };
  }

  // ---- 通報
  if (method === "GET" && p === "/api/reports") {
    const status = url.searchParams.get("status") ?? "open";
    const rows = db.prepare(`SELECT r.*, t.name AS target_name, rp.name AS reporter_name,
        (SELECT COUNT(*) FROM reports r2 WHERE r2.target_id = r.target_id) AS target_reports,
        (SELECT COUNT(*) FROM match_logs m WHERE m.match_id = r.match_id) AS has_log
      FROM reports r LEFT JOIN players t ON t.id = r.target_id LEFT JOIN players rp ON rp.id = r.reporter_id
      ${status === "all" ? "" : "WHERE r.status = ?"} ORDER BY r.id DESC LIMIT 200`).all(...((status === "all" ? [] : [status]) as never[]));
    return { reports: rows };
  }
  const rep = /^\/api\/reports\/(\d+)$/.exec(p);
  if (method === "POST" && rep) {
    const st = str(body.status, 20);
    if (!["open", "handled", "dismissed"].includes(st)) throw new AdminError(400, "状態は open / handled / dismissed");
    db.prepare("UPDATE reports SET status = ?, handled_at = ?, handled_note = ? WHERE id = ?").run(st, Date.now(), str(body.note, 300), Number(rep[1]));
    adminLog("report", `#${rep[1]}`, `通報を ${st} にした ${str(body.note, 300)}`);
    return { ok: true };
  }

  // ---- プレイヤー
  if (method === "GET" && p === "/api/players") {
    const q = (url.searchParams.get("q") ?? "").trim();
    const rows = db.prepare(`SELECT id, name, rating, wins, losses, draws, created_at, last_seen, banned_until, versus_banned_until,
        (SELECT COUNT(*) FROM reports r WHERE r.target_id = players.id) AS reports
      FROM players ${q ? "WHERE name LIKE ? OR id LIKE ?" : ""} ORDER BY last_seen DESC LIMIT 100`).all(...((q ? [`%${q}%`, `${q}%`] : []) as never[]));
    return { players: rows };
  }
  const pl = /^\/api\/players\/([0-9a-f-]{36})$/.exec(p);
  if (method === "GET" && pl) {
    const id = pl[1];
    const pr = db.prepare("SELECT id, name, rating, wins, losses, draws, title, created_at, last_seen FROM players WHERE id = ?").get(id);
    if (!pr) throw new AdminError(404, "見つかりません");
    return {
      player: pr,
      sanction: sanctionOf(id),
      reports_against: db.prepare("SELECT r.*, rp.name AS reporter_name FROM reports r LEFT JOIN players rp ON rp.id = r.reporter_id WHERE r.target_id = ? ORDER BY r.id DESC LIMIT 50").all(id),
      reports_by: db.prepare("SELECT COUNT(*) AS n FROM reports WHERE reporter_id = ?").get(id),
      matches: db.prepare(`SELECT m.*, a.name AS p1_name, b.name AS p2_name, (SELECT COUNT(*) FROM match_logs l WHERE l.match_id = m.id) AS has_log
        FROM matches m LEFT JOIN players a ON a.id = m.p1 LEFT JOIN players b ON b.id = m.p2 WHERE m.p1 = ? OR m.p2 = ? ORDER BY m.created_at DESC LIMIT 30`).all(id, id),
      history: db.prepare("SELECT * FROM admin_log WHERE target = ? ORDER BY id DESC LIMIT 30").all(id),
    };
  }
  const pa = /^\/api\/players\/([0-9a-f-]{36})\/action$/.exec(p);
  if (method === "POST" && pa) {
    const id = pa[1];
    const pr = playerById(id);
    if (!pr) throw new AdminError(404, "見つかりません");
    const type = str(body.type, 30);
    const reason = str(body.reason, 200);
    const hours = int(body.hours, 24);
    const until = hours <= 0 ? -1 : Date.now() + hours * 3_600_000;
    let detail = "";
    switch (type) {
      case "suspend": // 一時的な利用停止（scope: all = 全部 / versus = 対戦だけ）
      case "ban": {
        const forever = type === "ban";
        const t = forever ? -1 : until;
        if (str(body.scope, 10) === "versus" && !forever) setSanction(id, { versusBannedUntil: t, reason });
        else {
          setSanction(id, { bannedUntil: t, reason });
          kickPlayer(id, "このアカウントは利用停止になりました");
        }
        detail = forever ? `永久に利用停止（${reason}）` : `${str(body.scope, 10) === "versus" ? "対戦を" : ""}${hours}時間 利用停止（${reason}）`;
        break;
      }
      case "unban":
        setSanction(id, { bannedUntil: 0, versusBannedUntil: 0, reason: "" });
        detail = "利用停止を解除";
        break;
      case "reset_name":
        renamePlayer(id, cleanName(""));
        detail = `名前をリセット（前: ${pr.name}）`;
        break;
      case "reset_title":
        setPlayerTitle(id, "");
        detail = "称号をリセット";
        break;
      case "warn": {
        const msg = str(body.message, 300);
        if (msg === "") throw new AdminError(400, "警告の文を入れてください");
        setSanction(id, { warnMessage: msg });
        detail = `警告を送った: ${msg}`;
        break;
      }
      default:
        throw new AdminError(400, "その操作はありません");
    }
    adminLog("player_" + type, id, `${pr.name}: ${detail}`);
    return { ok: true, sanction: sanctionOf(id), banned: isActiveBan(sanctionOf(id).bannedUntil) };
  }

  // ---- 対戦
  if (method === "GET" && p === "/api/matches") {
    const rows = db.prepare(`SELECT m.*, a.name AS p1_name, b.name AS p2_name, (SELECT COUNT(*) FROM match_logs l WHERE l.match_id = m.id) AS has_log
      FROM matches m LEFT JOIN players a ON a.id = m.p1 LEFT JOIN players b ON b.id = m.p2 ORDER BY m.created_at DESC LIMIT 100`).all();
    return { matches: rows };
  }
  const ml = /^\/api\/matches\/([0-9a-f-]{36})\/log$/.exec(p);
  if (method === "GET" && ml) {
    const l = matchLog(ml[1]);
    if (!l) throw new AdminError(404, "この試合の会話は保存されていません（通報された試合だけ、30日保存）");
    adminLog("view_log", ml[1], "通報された試合の会話を見た");
    return { log: l };
  }

  // ---- AI の使用量と料金の目安
  if (method === "GET" && p === "/api/usage") {
    const rows = aiUsage(62).map((r) => ({ ...r, cost_usd: Math.round(costUsd(r.model, r) * 10000) / 10000 }));
    const now = new Date();
    const month = now.toISOString().slice(0, 7);
    const monthCost = rows.filter((r) => r.day.startsWith(month)).reduce((a, r) => a + r.cost_usd, 0);
    const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const projected = (monthCost / Math.max(1, now.getDate())) * daysInMonth;
    return {
      rows, month, month_cost_usd: Math.round(monthCost * 100) / 100, projected_usd: Math.round(projected * 100) / 100,
      budget_usd: runtime.monthlyBudgetUsd, over_budget: runtime.monthlyBudgetUsd > 0 && projected > runtime.monthlyBudgetUsd,
      prices: runtime.aiPrices,
    };
  }

  // ---- お知らせ
  if (method === "GET" && p === "/api/announcements") return { announcements: announcements(false) };
  if (method === "POST" && p === "/api/announcements") {
    const ja = str(body.ja, 300);
    if (ja === "") throw new AdminError(400, "日本語の文を入れてください");
    const id = addAnnouncement(ja, str(body.en, 300), str(body.zh, 300));
    adminLog("announce", `#${id}`, `お知らせを出した: ${ja}`);
    return { ok: true };
  }
  const an = /^\/api\/announcements\/(\d+)$/.exec(p);
  if (method === "POST" && an) {
    if (body.delete === true) deleteAnnouncement(Number(an[1]));
    else setAnnouncementActive(Number(an[1]), body.active === true);
    adminLog("announce", `#${an[1]}`, body.delete === true ? "お知らせを消した" : body.active === true ? "お知らせを出した" : "お知らせを下げた");
    return { ok: true };
  }

  // ---- 操作の記録
  if (method === "GET" && p === "/api/audit") return { logs: adminLogs(200) };

  throw new AdminError(404, "ありません");
}
