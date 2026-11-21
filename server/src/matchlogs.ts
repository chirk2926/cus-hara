// 通報された試合の会話（要件#100）。
// 試合の会話（文字。声の文字起こしを含む。声そのものは保存しない）は、ふだんはメモリにだけ置き、
// 試合が終わって1時間で捨てる。通報（プレイヤーの通報・自動の不適切発言の検出）があった試合だけを DB に保存し、
// 保存から30日で消す（purgeMatchLogs）。プライバシーポリシーに書いた扱いと同じ。
import { saveMatchLog } from "./db.ts";

const KEEP_AFTER_END_MS = 3_600_000;

interface Entry {
  body: Record<string, unknown>;
  ended: boolean;
  reported: boolean;
  until: number;
}

const recent = new Map<string, Entry>();

/** 試合が始まったとき・会話が増えたときに、今の会話を渡す（同じオブジェクトを使い続けてよい） */
export function trackMatch(matchId: string, body: Record<string, unknown>): void {
  const e = recent.get(matchId);
  if (e) e.body = body;
  else recent.set(matchId, { body, ended: false, reported: false, until: Number.MAX_SAFE_INTEGER });
}

/** 試合が終わった。通報があれば保存し、なければ1時間だけメモリに残す（終わったあとの通報のため） */
export function endMatch(matchId: string): void {
  const e = recent.get(matchId);
  if (!e) return;
  e.ended = true;
  e.until = Date.now() + KEEP_AFTER_END_MS;
  if (e.reported) saveMatchLog(matchId, e.body);
}

/** 試合中・終わって間もない試合の2人のID（覚えていなければ null） */
export function trackedPlayers(matchId: string): string[] | null {
  const e = recent.get(matchId);
  const ps = e?.body.players;
  return Array.isArray(ps) ? ps.map((p) => String((p as { id?: unknown }).id ?? "")) : null;
}

/** 通報があった。試合中なら終わったときに、終わっていれば今すぐ保存する */
export function markReported(matchId: string): void {
  const e = recent.get(matchId);
  if (!e) return;
  e.reported = true;
  if (e.ended) saveMatchLog(matchId, e.body);
}

setInterval(() => {
  const now = Date.now();
  for (const [id, e] of recent) if (e.ended && e.until < now) recent.delete(id);
}, 60_000).unref();
