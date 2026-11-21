// WebSocket（/ws）。対戦のマッチング・部屋・試合のやりとり。
// 接続したら最初に {"t":"auth","token":"..."} を送る。メッセージ一覧は docs/SERVER.md。
import { requestIp, banMessage, versusBlock } from "./http.ts";
import type http from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import { playerByToken } from "./db.ts";
import { type Conn, publicPlayer } from "./protocol.ts";
import type { Lobby } from "./lobby.ts";
import { allow } from "./ratelimit.ts";
import { config } from "./config.ts";
import { toLang } from "./lang.ts";
import { log } from "./log.ts";

const MAX_MESSAGE = 512 * 1024; // 音声20秒（μ-law 16kHz = 320KB）を base64 にしても収まる大きさ
const MAX_AUTH_MESSAGE = 4 * 1024; // ログイン前に受け付ける大きさ（要件#77）
const perIp = new Map<string, number>();

export function attachWebSocket(server: http.Server, lobby: Lobby): WebSocketServer {
  lobbyRef = lobby;
  const wss = new WebSocketServer({ server, path: "/ws", maxPayload: MAX_MESSAGE });
  const alive = new WeakMap<WebSocket, boolean>();

  const heartbeat = setInterval(() => {
    for (const ws of wss.clients) {
      if (alive.get(ws) === false) {
        ws.terminate();
        continue;
      }
      alive.set(ws, false);
      ws.ping();
    }
  }, 20_000);
  heartbeat.unref();

  wss.on("connection", (ws, req) => {
    const ip = requestIp(req);
    // 1つのIPからの同時接続数と、接続の速さを制限する（要件#77: 接続を大量に開いて重くさせない）
    const open = perIp.get(ip) ?? 0;
    if (open >= config.wsPerIp || !allow(`wsconn:${ip}`, 60, 60_000)) {
      ws.close(4029, "too many connections");
      return;
    }
    perIp.set(ip, open + 1);
    let counted = true;
    const release = () => {
      if (!counted) return;
      counted = false;
      const n = (perIp.get(ip) ?? 1) - 1;
      if (n <= 0) perIp.delete(ip);
      else perIp.set(ip, n);
    };
    alive.set(ws, true);
    ws.on("pong", () => alive.set(ws, true));
    let conn: Conn | null = null;
    const authTimer = setTimeout(() => {
      if (!conn) ws.close(4001, "auth timeout");
    }, 10_000);

    const sendRaw = (msg: Record<string, unknown>) => {
      if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
    };

    ws.on("message", (data, isBinary) => {
      if (isBinary) return;
      // ログイン前は小さなメッセージ（auth）だけ。それ以外は切る
      if (!conn && (data as Buffer).length > MAX_AUTH_MESSAGE) {
        ws.close(4001, "auth required");
        return;
      }
      let msg: Record<string, unknown>;
      try {
        msg = JSON.parse(data.toString());
      } catch {
        return;
      }
      if (typeof msg !== "object" || msg === null) return;
      const t = msg.t;
      if (!conn) {
        if (t !== "auth") {
          ws.close(4001, "auth required");
          return;
        }
        const player = typeof msg.token === "string" ? playerByToken(msg.token) : null;
        if (!player) {
          sendRaw({ t: "error", code: "unauthorized", message: "ログイン情報が無効です" });
          ws.close(4001, "unauthorized");
          return;
        }
        const ban = banMessage(player.id);
        if (ban) {
          sendRaw({ t: "error", code: "banned", message: ban });
          ws.close(4003, "banned");
          return;
        }
        clearTimeout(authTimer);
        conn = { player, lang: toLang(msg.lang), ip, send: sendRaw, close: (c, r) => ws.close(c, r) };
        // 同じアカウントの古い接続は切る（要件#108: 1つのアカウントで同時に1つだけ）
        for (const old of [...(live.get(player.id) ?? [])]) {
          old.send({ t: "error", code: "replaced", message: "ほかの場所でつながったので、こちらは切りました" });
          old.close(4001, "replaced");
        }
        registerConn(conn);
        ws.on("close", () => unregisterConn(conn!));
        const resumed = lobby.resume(conn);
        sendRaw({ t: "hello", player: publicPlayer(player), resumed });
        log("ws auth", player.name, resumed ? "(resumed)" : "");
        return;
      }
      if (!allow(`ws:${conn.player.id}`, 40, 10_000)) return; // 送りすぎは捨てる
      const c = conn;
      switch (t) {
        case "lang":
          c.lang = toLang(msg.lang);
          break;
        case "queue":
        case "room_create":
        case "room_join": {
          // メンテナンス中・対戦の利用停止中は始められない（要件#100）
          const blk = versusBlock(c.player.id);
          if (blk) {
            c.send({ t: "error", code: blk[0], message: blk[1] });
            break;
          }
          if (t === "queue") lobby.enqueue(c, msg.format);
          else if (t === "room_create") lobby.createRoom(c, msg.format, msg.answer_time, { ranked: msg.ranked, eos_lobby: msg.eos_lobby });
          else lobby.joinRoom(c, msg.code);
          break;
        }
        case "cancel":
          lobby.cancel(c);
          break;
        case "say": {
          const f = activeMatch(c);
          f?.match.onSay(f.seat, msg.text);
          break;
        }
        case "eos_voice": {
          const f = activeMatch(c);
          f?.match.onEosVoiceRoom(f.seat, msg.lobby_id);
          break;
        }
        case "eos_voice_ready": {
          const f = activeMatch(c);
          f?.match.onEosVoiceReady(f.seat, msg.ok);
          break;
        }
        case "voice": {
          const f = activeMatch(c);
          f?.match.onVoice(f.seat, msg.audio, msg.debug_text);
          break;
        }
        case "act": {
          const f = activeMatch(c);
          f?.match.onAction(f.seat, msg.id);
          break;
        }
        case "leave":
          lobby.leaveMatch(c);
          break;
        case "ping":
          sendRaw({ t: "pong" });
          break;
        default:
          break;
      }
    });

    ws.on("close", () => {
      release();
      clearTimeout(authTimer);
      if (conn) lobby.onDisconnect(conn);
    });
    ws.on("error", () => ws.terminate());
  });
  return wss;
}

/** その接続が今の席の接続のときだけ、対戦を返す（要件#108: 古い接続からの発言・行動は受け付けない） */
function activeMatch(c: Conn) {
  const f = lobbyRef?.matchOf(c.player.id);
  return f && f.match.seats[f.seat].conn === c ? f : undefined;
}

let lobbyRef: Lobby | null = null;

// ---------------------------------------------------------------- つながっている人（管理画面の利用停止で切るため。要件#100）

const live = new Map<string, Set<Conn>>();

function registerConn(c: Conn): void {
  const set = live.get(c.player.id) ?? new Set<Conn>();
  set.add(c);
  live.set(c.player.id, set);
}

function unregisterConn(c: Conn): void {
  const set = live.get(c.player.id);
  if (!set) return;
  set.delete(c);
  if (set.size === 0) live.delete(c.player.id);
}

/** そのプレイヤーの接続を切る（利用停止にしたとき） */
export function kickPlayer(id: string, message: string): number {
  const set = live.get(id);
  if (!set) return 0;
  for (const c of [...set]) {
    c.send({ t: "error", code: "banned", message });
    c.close(4003, "banned");
  }
  return set.size;
}

export function onlinePlayers(): number {
  return live.size;
}
