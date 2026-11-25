// 自動バックアップ（要件#131）。var/backups/<日時>/ に、DB（VACUUM INTO で、動いたまま一貫した写し）・
// APIキー（secrets.json）・管理画面のパスワード（admin_auth.json）・お知らせ／記事の画像を置く。
// 管理画面から: 設定（する・しない、間隔、残す数）、今すぐ取る、一覧、全部を戻す（再起動して入れかえる）、
// 指定したプレイヤーだけ戻す（バックアップの players の行を、今の DB に書き戻す）、消す。
// バックアップはこのマシンの中（サーバーのデータと同じ所）にだけ置く。外のディスクに写すのは運用で（docs/HOME_SERVER.md）。
import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { config } from "./config.ts";
import { openDb, closeDb } from "./db.ts";
import { log } from "./log.ts";
import { runtime } from "./settings.ts";

export class BackupError extends Error {}

const ID = /^\d{8}-\d{6}(-[a-z]+)?$/;

function varDir(): string | null {
  return config.dbPath === ":memory:" ? null : path.dirname(config.dbPath);
}
export function backupRoot(): string | null {
  const v = varDir();
  return v ? path.join(v, "backups") : null;
}
const stamp = (d = new Date()) => d.toISOString().replace(/[-:]/g, "").replace("T", "-").slice(0, 15);

function dirSize(p: string): number {
  let n = 0;
  for (const e of fs.readdirSync(p, { withFileTypes: true })) {
    const f = path.join(p, e.name);
    n += e.isDirectory() ? dirSize(f) : fs.statSync(f).size;
  }
  return n;
}

export interface BackupInfo {
  id: string;
  created: number;
  size: number;
  players: number;
  note: string;
}

export function listBackups(): BackupInfo[] {
  const root = backupRoot();
  if (!root || !fs.existsSync(root)) return [];
  const out: BackupInfo[] = [];
  for (const id of fs.readdirSync(root)) {
    if (!ID.test(id)) continue;
    const dir = path.join(root, id);
    try {
      const m = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf-8")) as { created: number; players: number; note?: string };
      out.push({ id, created: m.created, size: dirSize(dir), players: m.players, note: m.note ?? "" });
    } catch {
      // 途中で止まったもの・壊れたものは出さない
    }
  }
  return out.sort((a, b) => b.created - a.created);
}

/** 今のデータのバックアップを取る。戻り値は id */
export function createBackup(note = ""): string {
  const root = backupRoot();
  const v = varDir();
  if (!root || !v) throw new BackupError("メモリの DB では、バックアップは取れません");
  fs.mkdirSync(root, { recursive: true, mode: 0o700 });
  let id = stamp() + (note === "before-restore" ? "-prerestore" : "");
  while (fs.existsSync(path.join(root, id))) id += "x";
  const tmp = path.join(root, `.${id}.tmp`);
  fs.rmSync(tmp, { recursive: true, force: true });
  fs.mkdirSync(tmp, { mode: 0o700 });
  // DB: 動いたまま、一貫した写しを作る
  const dbFile = path.join(tmp, path.basename(config.dbPath));
  openDb().exec(`VACUUM INTO '${dbFile.replace(/'/g, "''")}'`);
  fs.chmodSync(dbFile, 0o600);
  for (const f of ["secrets.json", "admin_auth.json"]) {
    const src = path.join(v, f);
    if (fs.existsSync(src)) fs.copyFileSync(src, path.join(tmp, f));
  }
  const img = path.join(v, "notice_images");
  if (fs.existsSync(img)) fs.cpSync(img, path.join(tmp, "notice_images"), { recursive: true });
  const players = Number((openDb().prepare("SELECT COUNT(*) AS n FROM players").get() as { n: number }).n);
  fs.writeFileSync(path.join(tmp, "manifest.json"), JSON.stringify({ created: Date.now(), players, note }));
  fs.renameSync(tmp, path.join(root, id));
  prune();
  return id;
}

/** 残す数より古いものを消す（「全部を戻す」の直前に取った写しも数に入れる） */
function prune(): void {
  const root = backupRoot();
  if (!root) return;
  for (const b of listBackups().slice(Math.max(1, runtime.backupKeep))) fs.rmSync(path.join(root, b.id), { recursive: true, force: true });
}

export function deleteBackup(id: string): void {
  const root = backupRoot();
  if (!root || !ID.test(id) || !fs.existsSync(path.join(root, id))) throw new BackupError("そのバックアップはありません");
  fs.rmSync(path.join(root, id), { recursive: true, force: true });
}

function backupDb(id: string): string {
  const root = backupRoot();
  if (!root || !ID.test(id)) throw new BackupError("そのバックアップはありません");
  const f = path.join(root, id, path.basename(config.dbPath));
  if (!fs.existsSync(f)) throw new BackupError("そのバックアップはありません");
  return f;
}

/** バックアップの中のプレイヤーを探す（名前の一部か ID） */
export function backupPlayers(id: string, q: string): Array<{ id: string; name: string; rating: number; last_seen: number }> {
  const b = new DatabaseSync(backupDb(id), { readOnly: true });
  try {
    const like = `%${q.replace(/[%_]/g, "")}%`;
    return b.prepare("SELECT id, name, rating, last_seen FROM players WHERE name LIKE ? OR id = ? ORDER BY last_seen DESC LIMIT 50").all(like, q) as never;
  } finally {
    b.close();
  }
}

/** 指定したプレイヤーだけを、バックアップの時の状態に戻す（名前・レート・勝ち負け・称号・名札・見た目・利用停止など、players の行）。今いなければ作り直す */
export function restorePlayer(id: string, playerId: string): { name: string } {
  const b = new DatabaseSync(backupDb(id), { readOnly: true });
  let row: Record<string, unknown> | undefined;
  try {
    row = b.prepare("SELECT * FROM players WHERE id = ?").get(playerId) as Record<string, unknown> | undefined;
  } finally {
    b.close();
  }
  if (!row) throw new BackupError("そのバックアップに、そのプレイヤーはいません");
  const db = openDb();
  const liveCols = new Set((db.prepare("PRAGMA table_info(players)").all() as Array<{ name: string }>).map((c) => c.name));
  const cols = Object.keys(row).filter((c) => liveCols.has(c) && /^[a-z_]+$/.test(c));
  const vals = cols.map((c) => row![c] as never);
  db.prepare(`INSERT INTO players (${cols.join(", ")}) VALUES (${cols.map(() => "?").join(", ")})
    ON CONFLICT(id) DO UPDATE SET ${cols.filter((c) => c !== "id").map((c) => `${c} = excluded.${c}`).join(", ")}`).run(...vals);
  return { name: String(row.name ?? "") };
}

/** 全部を戻す: 次の起動で入れかえる印を置く（入れかえる前に、今のデータも写しておく） */
export function scheduleFullRestore(id: string): void {
  backupDb(id);
  const v = varDir()!;
  fs.writeFileSync(path.join(v, "restore_pending"), id, { mode: 0o600 });
}

/** 起動のとき（DB を開く前）: 全部を戻す印があれば入れかえる */
export function applyPendingRestore(): void {
  const v = varDir();
  if (!v) return;
  const mark = path.join(v, "restore_pending");
  if (!fs.existsSync(mark)) return;
  const id = fs.readFileSync(mark, "utf-8").trim();
  fs.rmSync(mark, { force: true });
  const root = backupRoot()!;
  const dir = path.join(root, id);
  if (!ID.test(id) || !fs.existsSync(dir)) {
    log("restore: backup not found", id);
    return;
  }
  // 戻す前の今のデータも写しておく（戻したのを取り消せるように）
  try {
    createBackup("before-restore");
  } catch (e) {
    log("restore: could not back up current data", String(e));
  }
  closeDb();
  const dbName = path.basename(config.dbPath);
  for (const suffix of ["", "-wal", "-shm"]) fs.rmSync(config.dbPath + suffix, { force: true });
  fs.copyFileSync(path.join(dir, dbName), config.dbPath);
  for (const f of ["secrets.json", "admin_auth.json"]) {
    const src = path.join(dir, f);
    if (fs.existsSync(src)) {
      fs.copyFileSync(src, path.join(v, f));
      fs.chmodSync(path.join(v, f), 0o600);
    }
  }
  const img = path.join(dir, "notice_images");
  if (fs.existsSync(img)) {
    fs.rmSync(path.join(v, "notice_images"), { recursive: true, force: true });
    fs.cpSync(img, path.join(v, "notice_images"), { recursive: true });
  }
  log("restore: restored from backup", id);
}

/** 決まった間隔で取る（10分ごとに、最後のバックアップからの時間を見る） */
export function startBackupTimer(): NodeJS.Timeout {
  return setInterval(() => {
    if (!runtime.backupEnabled || !backupRoot()) return;
    const last = listBackups().filter((b) => b.note !== "before-restore")[0];
    if (last && Date.now() - last.created < runtime.backupIntervalHours * 3_600_000) return;
    try {
      log("backup", createBackup());
    } catch (e) {
      log("backup failed", String(e));
    }
  }, 10 * 60_000).unref();
}
