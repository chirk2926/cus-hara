// WebSocket（/ws）。対戦のマッチング・部屋・試合のやりとり。
// 接続したら最初に {"t":"auth","token":"..."} を送る。メッセージ一覧は docs/SERVER.md。
import type http from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import { playerByToken } from "./db.ts";
import { type Conn, publicPlayer } from "./protocol.ts";
import type { Lobby } from "./lobby.ts";
import { allow } from "./ratelimit.ts";
import { toLang } from "./lang.ts";
import { log } from "./log.ts";

const MAX_MESSAGE = 512 * 1024; // 音声20秒（μ-law 16kHz = 320KB）を base64 にしても収まる大きさ

export function attachWebSocket(server: http.Server, lobby: Lobby): WebSocketServer {
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

  wss.on("connection", (ws) => {
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
      let msg: Record<string, unknown>;
      try {
        msg = JSON.parse(data.toString());
      } catch {
        return;
      }
      if (typeof msg !== "object" || msg === null) return;
      const t = msg.t;
      if (!conn) {
        if (t !== "auth") return;
        const player = typeof msg.token === "string" ? playerByToken(msg.token) : null;
        if (!player) {
          sendRaw({ t: "error", code: "unauthorized", message: "ログイン情報が無効です" });
          ws.close(4001, "unauthorized");
          return;
        }
        clearTimeout(authTimer);
        conn = { player, lang: toLang(msg.lang), send: sendRaw, close: (c, r) => ws.close(c, r) };
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
          lobby.enqueue(c, msg.format);
          break;
        case "cancel":
          lobby.cancel(c);
          break;
        case "room_create":
          lobby.createRoom(c, msg.format, msg.answer_time);
          break;
        case "room_join":
          lobby.joinRoom(c, msg.code);
          break;
        case "say": {
          const f = lobby.matchOf(c.player.id);
          f?.match.onSay(f.seat, msg.text);
          break;
        }
        case "voice": {
          const f = lobby.matchOf(c.player.id);
          f?.match.onVoice(f.seat, msg.audio, msg.debug_text);
          break;
        }
        case "act": {
          const f = lobby.matchOf(c.player.id);
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
      clearTimeout(authTimer);
      if (conn) lobby.onDisconnect(conn);
    });
    ws.on("error", () => ws.terminate());
  });
  return wss;
}
