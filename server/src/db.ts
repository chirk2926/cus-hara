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
  return db;
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
    .prepare("SELECT id, name, rating, wins, losses, draws, title FROM players WHERE token_hash = ?")
    .get(hashToken(token)) as Player | undefined;
  if (!row) return null;
  openDb().prepare("UPDATE players SET last_seen = ? WHERE id = ?").run(Date.now(), row.id);
  return { ...row };
}

export function playerById(id: string): Player | null {
  const row = openDb().prepare("SELECT id, name, rating, wins, losses, draws, title FROM players WHERE id = ?").get(id) as Player | undefined;
  return row ? { ...row } : null;
}

/** 称号の ID の形（"t" + 3桁）。中身（手に入れたか）はゲームのPCにあるので確かめられない（見た目だけのもの） */
export function cleanTitle(raw: unknown): string {
  return typeof raw === "string" && /^t\d{3}$/.test(raw) ? raw : "";
}

export function setPlayerTitle(id: string, title: string): void {
  openDb().prepare("UPDATE players SET title = ? WHERE id = ?").run(title, id);
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
