// マッチングとフレンド部屋。1人のプレイヤーは「待ち行列」「部屋」「試合」のどれか1つにしか入れない。
import crypto from "node:crypto";
import { config } from "./config.ts";
import { Match } from "./match.ts";
import type { Conn, Format } from "./protocol.ts";
import type { Lang } from "./lang.ts";
import { sttEnabled } from "./stt.ts";
import { log } from "./log.ts";

interface QueueEntry {
  conn: Conn;
  format: Format;
  lang: Lang;
  since: number;
  lastStatus: number;
}

interface Room {
  code: string;
  host: Conn;
  format: Format;
  lang: Lang;
  rateScale: number;
  kind: "ranked" | "friend";
  /** EOS のロビーID（EOS で組んだ部屋のとき） */
  eosLobby: string | null;
  created: number;
}

/** 部屋を作った人の「返事の時間」→ 怒りの速さの倍率（要件#35） */
const ANSWER_RATE: Record<string, number> = { slow: 0.6, normal: 1.0, fast: 1.4 };

const ROOM_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // 見間違えやすい I O 0 1 は使わない
const ROOM_TTL_MS = 15 * 60_000;

export class Lobby {
  private queue: QueueEntry[] = [];
  private rooms = new Map<string, Room>();
  private matches = new Map<string, Match>(); // player id -> match
  private timer: NodeJS.Timeout;

  constructor() {
    this.timer = setInterval(() => this.tick(), 500);
    this.timer.unref();
  }

  stats() {
    return { queued: this.queue.length, rooms: this.rooms.size, playing: this.matches.size };
  }

  private busy(playerId: string): string | null {
    if (this.matches.has(playerId)) return "試合中です";
    if (this.queue.some((q) => q.conn.player.id === playerId)) return "すでにマッチングを待っています";
    for (const r of this.rooms.values()) if (r.host.player.id === playerId) return "すでに部屋を作っています";
    return null;
  }

  private checkFormat(conn: Conn, format: unknown): Format | null {
    if (format !== "text" && format !== "voice") {
      conn.send({ t: "error", code: "bad_format", message: "対戦の形式（文字・音声）が正しくありません" });
      return null;
    }
    if (format === "voice" && !sttEnabled()) {
      conn.send({ t: "error", code: "voice_unavailable", message: "このサーバーは音声対戦に対応していません（文字起こしの設定がありません）" });
      return null;
    }
    return format;
  }

  // ---------------------------------------------------------------- ランクマッチ

  enqueue(conn: Conn, format: unknown): void {
    const f = this.checkFormat(conn, format);
    if (!f) return;
    const b = this.busy(conn.player.id);
    if (b) return void conn.send({ t: "error", code: "busy", message: b });
    this.queue.push({ conn, format: f, lang: conn.lang, since: Date.now(), lastStatus: 0 });
    conn.send({ t: "queued", format: f, lang: conn.lang });
    this.tick();
  }

  cancel(conn: Conn): void {
    const before = this.queue.length;
    this.queue = this.queue.filter((q) => q.conn.player.id !== conn.player.id);
    for (const [code, r] of this.rooms) if (r.host.player.id === conn.player.id) this.rooms.delete(code);
    if (before !== this.queue.length) conn.send({ t: "cancelled" });
  }

  /** 待ち時間に応じて広がる許容レーティング差 */
  private window(e: QueueEntry, now: number): number {
    const waited = ((now - e.since) / 1000) * config.timeScale;
    if (waited >= config.match.anyoneAfterSec) return Infinity;
    return config.match.startWindow + config.match.growPerSec * waited;
  }

  private tick(): void {
    const now = Date.now();
    // 古い部屋を片付ける
    for (const [code, r] of this.rooms) {
      if (now - r.created > ROOM_TTL_MS) {
        r.host.send({ t: "room_expired", code });
        this.rooms.delete(code);
      }
    }
    // 早く並んだ人から、許容範囲に入るいちばん近い相手を探す
    const sorted = [...this.queue].sort((a, b) => a.since - b.since);
    const paired = new Set<QueueEntry>();
    for (const a of sorted) {
      if (paired.has(a)) continue;
      let best: QueueEntry | null = null;
      let bestDiff = Infinity;
      for (const b of sorted) {
        // 同じ形式・同じ言語どうしだけを組む
        if (b === a || paired.has(b) || b.format !== a.format || b.lang !== a.lang || b.conn.player.id === a.conn.player.id) continue;
        // チート対策: 同じ回線（IP）どうしは組まない（1人で2つのアカウントを使ったレーティング稼ぎを防ぐ）
        if (!config.allowSameIpRanked && b.conn.ip === a.conn.ip) continue;
        const diff = Math.abs(a.conn.player.rating - b.conn.player.rating);
        if (diff <= this.window(a, now) && diff <= this.window(b, now) && diff < bestDiff) {
          best = b;
          bestDiff = diff;
        }
      }
      if (best) {
        paired.add(a);
        paired.add(best);
        this.startMatch("ranked", a.format, a.lang, a.conn, best.conn);
      }
    }
    this.queue = this.queue.filter((q) => !paired.has(q));
    for (const q of this.queue) {
      if (now - q.lastStatus >= 2000) {
        q.lastStatus = now;
        const w = this.window(q, now);
        q.conn.send({
          t: "queue_status",
          seconds: Math.floor(((now - q.since) / 1000) * config.timeScale),
          range: Number.isFinite(w) ? Math.round(w) : null,
          waiting_players: this.queue.filter((x) => x.format === q.format && x.lang === q.lang).length,
        });
      }
    }
  }

  // ---------------------------------------------------------------- フレンド対戦（部屋コード）

  /** opts.via_eos: EOS のロビーで組んだ相手と遊ぶ部屋（ranked: true ならランクマッチ。ALLOW_RANKED_ROOMS=1 のときだけ） */
  createRoom(conn: Conn, format: unknown, answerTime?: unknown, opts: { ranked?: unknown; eos_lobby?: unknown } = {}): void {
    const wantRanked = opts.ranked === true;
    if (wantRanked && !config.allowRankedRooms) {
      return void conn.send({ t: "error", code: "ranked_rooms_disabled", message: "このサーバーでは、部屋でのランクマッチは使えません" });
    }
    const f = this.checkFormat(conn, format);
    if (!f) return;
    const b = this.busy(conn.player.id);
    if (b) return void conn.send({ t: "error", code: "busy", message: b });
    let code = "";
    do {
      code = Array.from(crypto.randomBytes(6), (x) => ROOM_ALPHABET[x % ROOM_ALPHABET.length]).join("");
    } while (this.rooms.has(code));
    const eosLobby = typeof opts.eos_lobby === "string" ? opts.eos_lobby.slice(0, 64) : null;
    this.rooms.set(code, {
      code, host: conn, format: f, lang: conn.lang,
      // ランクマッチは公平のため返事の時間を固定
      rateScale: wantRanked ? 1 : ANSWER_RATE[String(answerTime)] ?? 1,
      kind: wantRanked ? "ranked" : "friend", eosLobby, created: Date.now(),
    });
    conn.send({ t: "room_created", code, format: f, lang: conn.lang });
  }

  joinRoom(conn: Conn, rawCode: unknown): void {
    const code = typeof rawCode === "string" ? rawCode.toUpperCase().replace(/[^A-Z0-9]/g, "") : "";
    const room = this.rooms.get(code);
    if (!room) return void conn.send({ t: "error", code: "room_not_found", message: "その部屋コードは見つかりません。コードを確かめるか、相手に作り直してもらってください" });
    if (room.host.player.id === conn.player.id) return void conn.send({ t: "error", code: "own_room", message: "自分の部屋には参加できません" });
    const b = this.busy(conn.player.id);
    if (b) return void conn.send({ t: "error", code: "busy", message: b });
    this.rooms.delete(code);
    // フレンド対戦は部屋を作った人の言語で進める
    this.startMatch(room.kind, room.format, room.lang, room.host, conn, room.rateScale);
  }

  // ---------------------------------------------------------------- 試合

  private startMatch(kind: "ranked" | "friend", format: Format, lang: Lang, a: Conn, b: Conn, rateScale = 1): void {
    const m = new Match(kind, format, lang, a, b);
    m.rateScale = rateScale;
    this.matches.set(a.player.id, m);
    this.matches.set(b.player.id, m);
    m.onEnd = (ended) => {
      for (const s of ended.seats) if (this.matches.get(s.player.id) === ended) this.matches.delete(s.player.id);
    };
    m.start();
  }

  matchOf(playerId: string): { match: Match; seat: number } | null {
    const m = this.matches.get(playerId);
    if (!m || m.finished) return null;
    return { match: m, seat: m.hasPlayer(playerId) };
  }

  /** 接続し直したプレイヤーを試合に戻す */
  resume(conn: Conn): boolean {
    const found = this.matchOf(conn.player.id);
    if (!found) return false;
    found.match.onReconnect(found.seat, conn);
    return true;
  }

  leaveMatch(conn: Conn): void {
    const found = this.matchOf(conn.player.id);
    if (found) found.match.forfeit(found.seat, "left");
  }

  onDisconnect(conn: Conn): void {
    this.queue = this.queue.filter((q) => q.conn !== conn);
    for (const [code, r] of this.rooms) if (r.host === conn) this.rooms.delete(code);
    const found = this.matchOf(conn.player.id);
    if (found && found.match.seats[found.seat].conn === conn) found.match.onDisconnect(found.seat);
    log("disconnect", conn.player.name);
  }
}
