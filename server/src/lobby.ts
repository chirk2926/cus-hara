// マッチングとフレンド部屋。1人のプレイヤーは「待ち行列」「部屋」「試合」のどれか1つにしか入れない。
import crypto from "node:crypto";
import { config } from "./config.ts";
import { Match } from "./match.ts";
import type { Conn, Format } from "./protocol.ts";
import type { Lang } from "./lang.ts";
import { sttEnabled } from "./stt.ts";
import { log } from "./log.ts";
import { runtime } from "./settings.ts";

/** 対戦のサーバー（要件#132）。1台の中で分ける。global は言語をまたいで組み、翻訳モードを選べる */
export type ServerId = Lang | "global";
export const SERVER_IDS: ServerId[] = ["ja", "en", "zh", "ko", "global"];
const SERVER_FLAG: Record<ServerId, keyof typeof runtime> = { ja: "vsServerJa", en: "vsServerEn", zh: "vsServerZh", ko: "vsServerKo", global: "vsServerGlobal" };
export function serverOpen(id: ServerId): boolean {
  return runtime[SERVER_FLAG[id]] === true;
}
/** ゲームに出すサーバーの一覧（開いているか） */
export function versusServers(): Array<{ id: ServerId; open: boolean }> {
  return SERVER_IDS.map((id) => ({ id, open: serverOpen(id) }));
}
/** グローバルの試合で、判定の文・お客さんの設定に使う言語 */
const GLOBAL_LANG: Lang = "en";

interface QueueEntry {
  conn: Conn;
  format: Format;
  server: ServerId;
  translate: boolean;
  since: number;
  lastStatus: number;
}

interface Room {
  code: string;
  host: Conn;
  format: Format;
  server: ServerId;
  translate: boolean;
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

  /** 選んだサーバー（無ければ自分の言語のサーバー）。閉じていたら断る */
  private checkServer(conn: Conn, server: unknown): ServerId | null {
    const id = (SERVER_IDS as string[]).includes(String(server)) ? (server as ServerId) : conn.lang;
    if (!serverOpen(id)) {
      conn.send({ t: "error", code: "server_closed", message: "そのサーバーは休止中です。ほかのサーバーを選んでください" });
      return null;
    }
    return id;
  }

  enqueue(conn: Conn, format: unknown, server?: unknown, translate?: unknown): void {
    const f = this.checkFormat(conn, format);
    if (!f) return;
    const sv = this.checkServer(conn, server);
    if (!sv) return;
    const b = this.busy(conn.player.id);
    if (b) return void conn.send({ t: "error", code: "busy", message: b });
    this.queue.push({ conn, format: f, server: sv, translate: sv === "global" && translate === true, since: Date.now(), lastStatus: 0 });
    conn.send({ t: "queued", format: f, lang: conn.lang, server: sv });
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
        // 同じ形式・同じサーバーどうしだけを組む（グローバルは言語をまたぐ）
        if (b === a || paired.has(b) || b.format !== a.format || b.server !== a.server || b.conn.player.id === a.conn.player.id) continue;
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
        this.startMatch("ranked", a.format, a.server, a.conn, best.conn, 1, [a.translate, best.translate]);
      }
    }
    this.queue = this.queue.filter((q) => !paired.has(q));
    for (const q of this.queue) {
      if (now - q.lastStatus >= 2000) {
        q.lastStatus = now;
        // レートの差（探している範囲）は出さない（要件#124）
        q.conn.send({
          t: "queue_status",
          seconds: Math.floor(((now - q.since) / 1000) * config.timeScale),
          waiting_players: this.queue.filter((x) => x.format === q.format && x.server === q.server).length,
        });
      }
    }
  }

  // ---------------------------------------------------------------- フレンド対戦（部屋コード）

  /** opts.via_eos: EOS のロビーで組んだ相手と遊ぶ部屋（ranked: true ならランクマッチ。ALLOW_RANKED_ROOMS=1 のときだけ） */
  createRoom(conn: Conn, format: unknown, answerTime?: unknown, opts: { ranked?: unknown; eos_lobby?: unknown; server?: unknown; translate?: unknown } = {}): void {
    const wantRanked = opts.ranked === true;
    if (wantRanked && !config.allowRankedRooms) {
      return void conn.send({ t: "error", code: "ranked_rooms_disabled", message: "このサーバーでは、部屋でのランクマッチは使えません" });
    }
    const f = this.checkFormat(conn, format);
    if (!f) return;
    const sv = this.checkServer(conn, opts.server);
    if (!sv) return;
    const b = this.busy(conn.player.id);
    if (b) return void conn.send({ t: "error", code: "busy", message: b });
    let code = "";
    do {
      code = Array.from(crypto.randomBytes(6), (x) => ROOM_ALPHABET[x % ROOM_ALPHABET.length]).join("");
    } while (this.rooms.has(code));
    const eosLobby = typeof opts.eos_lobby === "string" ? opts.eos_lobby.slice(0, 64) : null;
    this.rooms.set(code, {
      code, host: conn, format: f, server: sv, translate: sv === "global" && opts.translate === true,
      // ランクマッチは公平のため返事の時間を固定
      rateScale: wantRanked ? 1 : (Object.hasOwn(ANSWER_RATE, String(answerTime)) ? ANSWER_RATE[String(answerTime)] : 1),
      kind: wantRanked ? "ranked" : "friend", eosLobby, created: Date.now(),
    });
    conn.send({ t: "room_created", code, format: f, lang: conn.lang, server: sv });
  }

  joinRoom(conn: Conn, rawCode: unknown, translate?: unknown): void {
    const code = typeof rawCode === "string" ? rawCode.toUpperCase().replace(/[^A-Z0-9]/g, "") : "";
    const room = this.rooms.get(code);
    if (!room) return void conn.send({ t: "error", code: "room_not_found", message: "その部屋コードは見つかりません。コードを確かめるか、相手に作り直してもらってください" });
    if (room.host.player.id === conn.player.id) return void conn.send({ t: "error", code: "own_room", message: "自分の部屋には参加できません" });
    const b = this.busy(conn.player.id);
    if (b) return void conn.send({ t: "error", code: "busy", message: b });
    // ランクの部屋（EOS で組んだ相手）のチート対策: 同じ回線どうし・レーティング差が大きすぎる相手は不可
    if (room.kind === "ranked") {
      if (!config.allowSameIpRanked && room.host.ip === conn.ip) {
        return void conn.send({ t: "error", code: "same_network", message: "同じ回線のプレイヤーどうしでは、ランクマッチはできません" });
      }
      if (Math.abs(room.host.player.rating - conn.player.rating) > config.rankedRoomMaxGap) {
        return void conn.send({ t: "error", code: "rating_gap", message: "レーティングの差が大きすぎるため、このランクマッチには入れません" });
      }
    }
    if (!serverOpen(room.server)) return void conn.send({ t: "error", code: "server_closed", message: "その部屋のサーバーは休止中です" });
    this.rooms.delete(code);
    // 部屋のサーバーで進める（言語のサーバーなら、その言語。グローバルなら言語をまたぐ）
    this.startMatch(room.kind, room.format, room.server, room.host, conn, room.rateScale, [room.translate, room.server === "global" && translate === true]);
  }

  // ---------------------------------------------------------------- 試合

  private startMatch(kind: "ranked" | "friend", format: Format, server: ServerId, a: Conn, b: Conn, rateScale = 1, translate: [boolean, boolean] = [false, false]): void {
    const m = new Match(kind, format, server === "global" ? GLOBAL_LANG : server, a, b, { server, translate });
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
