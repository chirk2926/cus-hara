// データベース（Node 標準の SQLite）。プレイヤー・レーティング・対戦記録を保存する。
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import { config } from "./config.ts";
import { RATING_START } from "./rating.ts";

export interface Player {
  id: string;
  name: string;
  rating: number;
  wins: number;
  losses: number;
  draws: number;
  /** つけている称号の ID（要件#79。"t001" など。無ければ ""） */
  title?: string;
  /** 名札の飾り（要件#82）。"枠:名前の色:スタンプ"（ショップで買ったものの ID。無ければ ""） */
  tag?: string;
  /** 対戦のキャラクター（要件#84）。cleanAvatar を通した JSON（無ければ ""） */
  avatar?: string;
}

let db: DatabaseSync | null = null;

export function openDb(): DatabaseSync {
  if (db !== null) return db;
  if (config.dbPath !== ":memory:") fs.mkdirSync(path.dirname(config.dbPath), { recursive: true });
  db = new DatabaseSync(config.dbPath);
  db.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS players (
      id TEXT PRIMARY KEY,
      token_hash TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      rating INTEGER NOT NULL DEFAULT ${RATING_START},
      wins INTEGER NOT NULL DEFAULT 0,
      losses INTEGER NOT NULL DEFAULT 0,
      draws INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      last_seen INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS reports (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      reporter_id TEXT NOT NULL,
      target_id TEXT NOT NULL,
      match_id TEXT NOT NULL DEFAULT '',
      reason TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      UNIQUE (reporter_id, target_id, match_id)
    );
    CREATE TABLE IF NOT EXISTS matches (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      format TEXT NOT NULL,
      stage TEXT NOT NULL,
      p1 TEXT NOT NULL,
      p2 TEXT NOT NULL,
      p1_points INTEGER NOT NULL,
      p2_points INTEGER NOT NULL,
      winner TEXT,
      p1_delta INTEGER NOT NULL,
      p2_delta INTEGER NOT NULL,
      ended_reason TEXT NOT NULL,
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_players_rating ON players(rating DESC);
  `);
  // 称号の列（要件#79）。古いDBには後から足す
  const cols = db.prepare("PRAGMA table_info(players)").all() as Array<{ name: string }>;
  if (!cols.some((c) => c.name === "title")) db.exec("ALTER TABLE players ADD COLUMN title TEXT NOT NULL DEFAULT ''");
  // 名札の飾りの列（要件#82）
  if (!cols.some((c) => c.name === "tag")) db.exec("ALTER TABLE players ADD COLUMN tag TEXT NOT NULL DEFAULT ''");
  // 対戦のキャラクターの列（要件#84）
  if (!cols.some((c) => c.name === "avatar")) db.exec("ALTER TABLE players ADD COLUMN avatar TEXT NOT NULL DEFAULT ''");
  // 利用停止・警告（要件#100。管理画面から）。banned_until: 0 = なし、-1 = 永久、それ以外はその時刻（ミリ秒）まで
  for (const [col, def] of [["banned_until", "INTEGER NOT NULL DEFAULT 0"], ["versus_banned_until", "INTEGER NOT NULL DEFAULT 0"],
    ["ban_reason", "TEXT NOT NULL DEFAULT ''"], ["warn_message", "TEXT NOT NULL DEFAULT ''"],
    // 対戦の発言の取り扱いへの同意（要件#101）。どの版の文に、いつ同意したか（0 = 同意していない・取り消した）
    ["vs_consent_version", "INTEGER NOT NULL DEFAULT 0"], ["vs_consent_at", "INTEGER NOT NULL DEFAULT 0"]] as const) {
    if (!cols.some((c) => c.name === col)) db.exec(`ALTER TABLE players ADD COLUMN ${col} ${def}`);
  }
  // 通報の対応状況（要件#100）
  const rcols = db.prepare("PRAGMA table_info(reports)").all() as Array<{ name: string }>;
  for (const [col, def] of [["status", "TEXT NOT NULL DEFAULT 'open'"], ["handled_at", "INTEGER NOT NULL DEFAULT 0"], ["handled_note", "TEXT NOT NULL DEFAULT ''"]] as const) {
    if (!rcols.some((c) => c.name === col)) db.exec(`ALTER TABLE reports ADD COLUMN ${col} ${def}`);
  }
  db.exec(`
    -- 通報された試合の会話（文字だけ。声は保存しない）。30日で消す（要件#100・プライバシーポリシー）
    CREATE TABLE IF NOT EXISTS match_logs (
      match_id TEXT PRIMARY KEY,
      created_at INTEGER NOT NULL,
      body TEXT NOT NULL
    );
    -- AI の使用量（日ごと・モデルごと）。料金の目安に使う
    CREATE TABLE IF NOT EXISTS ai_usage (
      day TEXT NOT NULL,
      model TEXT NOT NULL,
      calls INTEGER NOT NULL DEFAULT 0,
      input INTEGER NOT NULL DEFAULT 0,
      output INTEGER NOT NULL DEFAULT 0,
      cache_read INTEGER NOT NULL DEFAULT 0,
      cache_write INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (day, model)
    );
    -- お知らせ（タイトル画面に出す）
    CREATE TABLE IF NOT EXISTS announcements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      text_ja TEXT NOT NULL,
      text_en TEXT NOT NULL DEFAULT '',
      text_zh TEXT NOT NULL DEFAULT '',
      active INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL
    );
    -- 管理画面で変えた設定（秘密の値は var/secrets.json に別に置く）
    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );
    -- 管理画面の操作の記録（戻すときに使う）
    CREATE TABLE IF NOT EXISTS admin_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      at INTEGER NOT NULL,
      action TEXT NOT NULL,
      target TEXT NOT NULL DEFAULT '',
      detail TEXT NOT NULL DEFAULT '',
      before_value TEXT NOT NULL DEFAULT '',
      after_value TEXT NOT NULL DEFAULT ''
    );
    CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status, created_at);
    CREATE INDEX IF NOT EXISTS idx_matches_created ON matches(created_at);
  `);
  // お知らせの見出し・フォント・画像（要件#100: Markdown で書け、画像を載せ、フォントを選べる）
  const acols = db.prepare("PRAGMA table_info(announcements)").all() as Array<{ name: string }>;
  for (const [col, def] of [["title_ja", "TEXT NOT NULL DEFAULT ''"], ["title_en", "TEXT NOT NULL DEFAULT ''"], ["title_zh", "TEXT NOT NULL DEFAULT ''"],
    ["title_ko", "TEXT NOT NULL DEFAULT ''"], ["text_ko", "TEXT NOT NULL DEFAULT ''"],
    ["font", "TEXT NOT NULL DEFAULT 'body'"], ["image", "TEXT NOT NULL DEFAULT ''"]] as const) {
    if (!acols.some((c) => c.name === col)) db.exec(`ALTER TABLE announcements ADD COLUMN ${col} ${def}`);
  }
  return db;
}

// ---------------------------------------------------------------- 利用停止・警告（要件#100）

export interface Sanction {
  bannedUntil: number;
  versusBannedUntil: number;
  reason: string;
  warnMessage: string;
}

export function sanctionOf(id: string): Sanction {
  const r = openDb().prepare("SELECT banned_until, versus_banned_until, ban_reason, warn_message FROM players WHERE id = ?").get(id) as
    | { banned_until: number; versus_banned_until: number; ban_reason: string; warn_message: string }
    | undefined;
  return { bannedUntil: Number(r?.banned_until ?? 0), versusBannedUntil: Number(r?.versus_banned_until ?? 0), reason: r?.ban_reason ?? "", warnMessage: r?.warn_message ?? "" };
}

/** 今止められているか。until: 0 = なし、-1 = 永久 */
export function isActiveBan(until: number, now = Date.now()): boolean {
  return until === -1 || until > now;
}

export function setSanction(id: string, s: Partial<Sanction>): void {
  const cur = sanctionOf(id);
  const n = { ...cur, ...s };
  openDb().prepare("UPDATE players SET banned_until = ?, versus_banned_until = ?, ban_reason = ?, warn_message = ? WHERE id = ?")
    .run(n.bannedUntil, n.versusBannedUntil, n.reason.slice(0, 200), n.warnMessage.slice(0, 300), id);
}

// ---------------------------------------------------------------- アカウントの削除（要件#101: 退職でサーバーのデータも消す）

/**
 * プレイヤーのデータを消す: アカウント（名前・レート・称号・飾り・キャラクター・同意の記録）、この人がした通報・この人への通報、
 * この人が出た試合の保存された会話。対戦の記録（matches）は相手のレートの計算のために残すが、ID だけで名前は消える。
 */
export function deletePlayer(id: string): void {
  const d = openDb();
  d.exec("BEGIN");
  try {
    const ms = d.prepare("SELECT id FROM matches WHERE p1 = ? OR p2 = ?").all(id, id) as Array<{ id: string }>;
    for (const m of ms) d.prepare("DELETE FROM match_logs WHERE match_id = ?").run(m.id);
    d.prepare("DELETE FROM reports WHERE reporter_id = ? OR target_id = ?").run(id, id);
    d.prepare("DELETE FROM players WHERE id = ?").run(id);
    d.exec("COMMIT");
  } catch (e) {
    d.exec("ROLLBACK");
    throw e;
  }
}

// ---------------------------------------------------------------- 対戦の同意（要件#101）

/**
 * 対戦の発言（ユーザーどうしの通信）を、チェック・AIの判定・外部のAIへの送信・通報された試合の保存に使うことへの同意の版。
 * 同意の画面の文（ゲームの scripts/consent.gd）を大きく変えたら上げる（もう一度同意してもらう）
 */
export const VS_CONSENT_VERSION = 1;

export function consentOf(id: string): { version: number; at: number } {
  const r = openDb().prepare("SELECT vs_consent_version, vs_consent_at FROM players WHERE id = ?").get(id) as { vs_consent_version: number; vs_consent_at: number } | undefined;
  return { version: Number(r?.vs_consent_version ?? 0), at: Number(r?.vs_consent_at ?? 0) };
}

/** 同意する（version）・取り消す（0） */
export function setConsent(id: string, version: number): void {
  openDb().prepare("UPDATE players SET vs_consent_version = ?, vs_consent_at = ? WHERE id = ?").run(version, Date.now(), id);
}

export function hasConsent(id: string): boolean {
  return consentOf(id).version >= VS_CONSENT_VERSION;
}

// ---------------------------------------------------------------- 通報された試合の会話（要件#100）

export const MATCH_LOG_DAYS = 30;

export function saveMatchLog(matchId: string, body: unknown): void {
  openDb().prepare("INSERT OR REPLACE INTO match_logs (match_id, created_at, body) VALUES (?, ?, ?)").run(matchId, Date.now(), JSON.stringify(body));
}

export function matchLog(matchId: string): unknown | null {
  const r = openDb().prepare("SELECT body FROM match_logs WHERE match_id = ?").get(matchId) as { body: string } | undefined;
  return r ? JSON.parse(r.body) : null;
}

/** 保存期間を過ぎた会話（30日）と通報（1年）を消す。消した会話の数を返す（プライバシーポリシー） */
export const REPORT_KEEP_DAYS = 365;

export function purgeMatchLogs(now = Date.now()): number {
  const r = openDb().prepare("DELETE FROM match_logs WHERE created_at < ?").run(now - MATCH_LOG_DAYS * 86_400_000);
  openDb().prepare("DELETE FROM reports WHERE created_at < ?").run(now - REPORT_KEEP_DAYS * 86_400_000);
  return Number(r.changes);
}

// ---------------------------------------------------------------- AI の使用量（要件#100）

export function addAiUsage(model: string, u: { input: number; output: number; cacheRead: number; cacheWrite: number }, now = new Date()): void {
  const day = now.toISOString().slice(0, 10);
  openDb()
    .prepare(`INSERT INTO ai_usage (day, model, calls, input, output, cache_read, cache_write) VALUES (?, ?, 1, ?, ?, ?, ?)
      ON CONFLICT(day, model) DO UPDATE SET calls = calls + 1, input = input + excluded.input, output = output + excluded.output,
      cache_read = cache_read + excluded.cache_read, cache_write = cache_write + excluded.cache_write`)
    .run(day, model, u.input, u.output, u.cacheRead, u.cacheWrite);
}

export function aiUsage(days: number): Array<{ day: string; model: string; calls: number; input: number; output: number; cache_read: number; cache_write: number }> {
  const since = new Date(Date.now() - days * 86_400_000).toISOString().slice(0, 10);
  return openDb().prepare("SELECT * FROM ai_usage WHERE day >= ? ORDER BY day DESC, model").all(since) as never;
}

// ---------------------------------------------------------------- お知らせ・設定・操作の記録（要件#100）

export interface Announcement {
  id: number;
  title_ja: string;
  title_en: string;
  title_zh: string;
  title_ko: string;
  /** 本文（Markdown） */
  text_ja: string;
  text_en: string;
  text_zh: string;
  text_ko: string;
  /** フォント: body（本文）/ hand（手書き）/ dot（ドット）/ sign（看板の極太） */
  font: string;
  /** 画像のファイル名（var/notice_images の中。無ければ ""） */
  image: string;
  active: number;
  created_at: number;
}

export const NOTICE_FONTS = ["body", "hand", "dot", "sign"] as const;

export interface AnnouncementInput {
  title_ja: string; title_en: string; title_zh: string; title_ko: string;
  text_ja: string; text_en: string; text_zh: string; text_ko: string;
  font: string; image: string;
}

export function announcements(activeOnly: boolean): Announcement[] {
  return openDb().prepare(`SELECT * FROM announcements ${activeOnly ? "WHERE active = 1" : ""} ORDER BY id DESC LIMIT 50`).all() as never;
}

function cleanAnnouncement(a: AnnouncementInput): AnnouncementInput {
  const t = (v: string, n: number) => String(v ?? "").replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, "").slice(0, n);
  return {
    title_ja: t(a.title_ja, 80), title_en: t(a.title_en, 80), title_zh: t(a.title_zh, 80), title_ko: t(a.title_ko, 80),
    text_ja: t(a.text_ja, 4000), text_en: t(a.text_en, 4000), text_zh: t(a.text_zh, 4000), text_ko: t(a.text_ko, 4000),
    font: (NOTICE_FONTS as readonly string[]).includes(a.font) ? a.font : "body",
    image: /^[0-9a-f]{32}\.(png|jpg)$/.test(a.image) ? a.image : "",
  };
}

export function addAnnouncement(input: AnnouncementInput): number {
  const a = cleanAnnouncement(input);
  const r = openDb().prepare(`INSERT INTO announcements (title_ja, title_en, title_zh, title_ko, text_ja, text_en, text_zh, text_ko, font, image, active, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)`).run(a.title_ja, a.title_en, a.title_zh, a.title_ko, a.text_ja, a.text_en, a.text_zh, a.text_ko, a.font, a.image, Date.now());
  return Number(r.lastInsertRowid);
}

export function updateAnnouncement(id: number, input: AnnouncementInput): void {
  const a = cleanAnnouncement(input);
  openDb().prepare("UPDATE announcements SET title_ja = ?, title_en = ?, title_zh = ?, title_ko = ?, text_ja = ?, text_en = ?, text_zh = ?, text_ko = ?, font = ?, image = ? WHERE id = ?")
    .run(a.title_ja, a.title_en, a.title_zh, a.title_ko, a.text_ja, a.text_en, a.text_zh, a.text_ko, a.font, a.image, id);
}

export function setAnnouncementActive(id: number, active: boolean): void {
  openDb().prepare("UPDATE announcements SET active = ? WHERE id = ?").run(active ? 1 : 0, id);
}

export function deleteAnnouncement(id: number): void {
  openDb().prepare("DELETE FROM announcements WHERE id = ?").run(id);
}

export function storedSettings(): Record<string, string> {
  const rows = openDb().prepare("SELECT key, value FROM settings").all() as Array<{ key: string; value: string }>;
  return Object.fromEntries(rows.map((r) => [r.key, r.value]));
}

export function storeSetting(key: string, value: string | null): void {
  if (value === null) openDb().prepare("DELETE FROM settings WHERE key = ?").run(key);
  else openDb().prepare("INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (?, ?, ?)").run(key, value, Date.now());
}

export function adminLog(action: string, target: string, detail: string, before = "", after = ""): number {
  const r = openDb().prepare("INSERT INTO admin_log (at, action, target, detail, before_value, after_value) VALUES (?, ?, ?, ?, ?, ?)")
    .run(Date.now(), action, target.slice(0, 200), detail.slice(0, 500), before.slice(0, 2000), after.slice(0, 2000));
  return Number(r.lastInsertRowid);
}

export function adminLogs(limit: number): Array<{ id: number; at: number; action: string; target: string; detail: string; before_value: string; after_value: string }> {
  return openDb().prepare("SELECT * FROM admin_log ORDER BY id DESC LIMIT ?").all(limit) as never;
}

export function adminLogById(id: number): { id: number; action: string; target: string; before_value: string; after_value: string } | undefined {
  return openDb().prepare("SELECT * FROM admin_log WHERE id = ?").get(id) as never;
}

export function hashToken(token: string): string {
  return crypto.createHash("sha256").update(token).digest("hex");
}

export function cleanName(raw: unknown): string {
  const s = typeof raw === "string" ? raw : "";
  const cleaned = s.replace(/[\u0000-\u001f\u007f<>]/g, "").trim().slice(0, 16);
  return cleaned === "" ? "名無しのスタッフ" : cleaned;
}

export function createPlayer(name: string): { player: Player; token: string } {
  const id = crypto.randomUUID();
  const token = crypto.randomBytes(32).toString("base64url");
  const now = Date.now();
  openDb()
    .prepare("INSERT INTO players (id, token_hash, name, created_at, last_seen) VALUES (?, ?, ?, ?, ?)")
    .run(id, hashToken(token), name, now, now);
  return { player: { id, name, rating: RATING_START, wins: 0, losses: 0, draws: 0 }, token };
}

export function playerByToken(token: string): Player | null {
  const row = openDb()
    .prepare("SELECT id, name, rating, wins, losses, draws, title, tag, avatar FROM players WHERE token_hash = ?")
    .get(hashToken(token)) as Player | undefined;
  if (!row) return null;
  openDb().prepare("UPDATE players SET last_seen = ? WHERE id = ?").run(Date.now(), row.id);
  return { ...row };
}

export function playerById(id: string): Player | null {
  const row = openDb().prepare("SELECT id, name, rating, wins, losses, draws, title, tag, avatar FROM players WHERE id = ?").get(id) as Player | undefined;
  return row ? { ...row } : null;
}

/** 称号の ID の形（"t" + 3桁）。中身（手に入れたか）はゲームのPCにあるので確かめられない（見た目だけのもの） */
export function cleanTitle(raw: unknown): string {
  return typeof raw === "string" && /^t\d{3}$/.test(raw) ? raw : "";
}

export function setPlayerTitle(id: string, title: string): void {
  openDb().prepare("UPDATE players SET title = ? WHERE id = ?").run(title, id);
}

/** 名札の飾り: {frame, color, stamp}（それぞれ英小文字・数字・_ の16文字まで）を "frame:color:stamp" にする。形の違う値は "" */
export function cleanTag(raw: unknown): string {
  if (typeof raw !== "object" || raw === null) return "";
  const r = raw as Record<string, unknown>;
  const part = (v: unknown): string => (typeof v === "string" && /^[a-z0-9_]{1,16}$/.test(v) ? v : "");
  const parts = [part(r.frame), part(r.color), part(r.stamp)];
  return parts.every((x) => x === "") ? "" : parts.join(":");
}

export function setPlayerTag(id: string, tag: string): void {
  openDb().prepare("UPDATE players SET tag = ? WHERE id = ?").run(tag, id);
}

/** 対戦のキャラクター: 決まった項目だけ（ID は英小文字・数字・_ の16文字まで、身長は 0.85〜1.15）。形の違う値は "" */
export function cleanAvatar(raw: unknown): string {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return "";
  const r = raw as Record<string, unknown>;
  const id = (v: unknown, ok?: string[]): string => {
    const s = typeof v === "string" && /^[a-z0-9_]{1,16}$/.test(v) ? v : "";
    return ok && !ok.includes(s) ? "" : s;
  };
  const h = typeof r.height === "number" && Number.isFinite(r.height) ? Math.min(1.15, Math.max(0.85, r.height)) : 1;
  const out = {
    gender: id(r.gender, ["m", "f", "x"]) || "x",
    height: Math.round(h * 100) / 100,
    build: id(r.build, ["slim", "normal", "big"]) || "normal",
    skin: id(r.skin),
    hair: id(r.hair),
    hair_color: id(r.hair_color),
    casual: id(r.casual),
    uniform: id(r.uniform),
    acc: id(r.acc),
    // ネタのアイテム（要件#86）
    head: id(r.head),
    face: id(r.face),
    hand: id(r.hand),
    body: id(r.body),
  };
  return JSON.stringify(out);
}

export function setPlayerAvatar(id: string, avatar: string): void {
  openDb().prepare("UPDATE players SET avatar = ? WHERE id = ?").run(avatar, id);
}

export function renamePlayer(id: string, name: string): void {
  openDb().prepare("UPDATE players SET name = ? WHERE id = ?").run(name, id);
}

export interface MatchRecord {
  id: string;
  kind: "ranked" | "friend";
  format: "text" | "voice";
  stage: string;
  p1: string;
  p2: string;
  p1Points: number;
  p2Points: number;
  winner: string | null;
  p1Delta: number;
  p2Delta: number;
  endedReason: string;
}

/** 対戦結果を記録し、ランクマッチならレーティングと勝敗数を更新する（1つのトランザクションで） */
export function recordMatch(m: MatchRecord): void {
  const d = openDb();
  d.exec("BEGIN");
  try {
    d.prepare(
      "INSERT INTO matches (id, kind, format, stage, p1, p2, p1_points, p2_points, winner, p1_delta, p2_delta, ended_reason, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    ).run(m.id, m.kind, m.format, m.stage, m.p1, m.p2, m.p1Points, m.p2Points, m.winner, m.p1Delta, m.p2Delta, m.endedReason, Date.now());
    if (m.kind === "ranked") {
      for (const [pid, delta] of [[m.p1, m.p1Delta], [m.p2, m.p2Delta]] as Array<[string, number]>) {
        const col = m.winner === null ? "draws" : m.winner === pid ? "wins" : "losses";
        d.prepare(`UPDATE players SET rating = MAX(0, rating + ?), ${col} = ${col} + 1 WHERE id = ?`).run(delta, pid);
      }
    }
    d.exec("COMMIT");
  } catch (e) {
    d.exec("ROLLBACK");
    throw e;
  }
}

/** 24時間以内に、この2人がランクマッチで当たった回数（チート対策） */
export function recentPairCount(a: string, b: string): number {
  const since = Date.now() - 24 * 3_600_000;
  const row = openDb()
    .prepare("SELECT COUNT(*) AS n FROM matches WHERE kind = 'ranked' AND created_at >= ? AND ((p1 = ? AND p2 = ?) OR (p1 = ? AND p2 = ?))")
    .get(since, a, b, b, a) as { n: number } | undefined;
  return row ? Number(row.n) : 0;
}

export function leaderboard(limit: number): Array<{ rank: number; name: string; rating: number; wins: number; losses: number }> {
  const rows = openDb()
    .prepare("SELECT name, rating, wins, losses FROM players WHERE wins + losses + draws > 0 ORDER BY rating DESC, wins DESC LIMIT ?")
    .all(limit) as Array<{ name: string; rating: number; wins: number; losses: number }>;
  return rows.map((r, i) => ({ rank: i + 1, ...r }));
}

/** プレイヤーの通報（要件#87）。理由は決まった中から。メモは 200 文字まで */
export const REPORT_REASONS = ["abuse", "sexual", "personal_info", "cheating", "afk", "other"] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];

/** 通報を保存する。同じ相手・同じ試合への2回目は保存しない（false） */
export function addReport(reporterId: string, targetId: string, matchId: string, reason: ReportReason, note: string): boolean {
  const r = openDb()
    .prepare("INSERT OR IGNORE INTO reports (reporter_id, target_id, match_id, reason, note, created_at) VALUES (?, ?, ?, ?, ?, ?)")
    .run(reporterId, targetId, matchId, reason, note, Date.now());
  return Number(r.changes) > 0;
}

/** 運営が見る用: そのプレイヤーへの通報の数 */
export function reportCount(targetId: string): number {
  const row = openDb().prepare("SELECT COUNT(*) AS n FROM reports WHERE target_id = ?").get(targetId) as { n: number };
  return Number(row.n);
}

