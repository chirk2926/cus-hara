// テスト用: サーバーをこのプロセス内で起動し、HTTP と WebSocket で操作する
import type { AddressInfo } from "node:net";
import WebSocket from "ws";

process.env.LLM_MODE = "offline";
process.env.STT_PROVIDER = "mock";
process.env.DB_PATH = ":memory:";
process.env.TIME_SCALE = "25";
process.env.QUIET = "1";
process.env.GUESTS_PER_HOUR = "1000";
process.env.ALLOW_SAME_IP_RANKED = "1";

const { openDb } = await import("../src/db.ts");
const { Lobby } = await import("../src/lobby.ts");
const { createHttpServer } = await import("../src/http.ts");
const { attachWebSocket } = await import("../src/ws.ts");

export async function startServer() {
  openDb();
  const lobby = new Lobby();
  const server = createHttpServer(lobby);
  const wss = attachWebSocket(server, lobby);
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", () => r()));
  const port = (server.address() as AddressInfo).port;
  return {
    base: `http://127.0.0.1:${port}`,
    wsUrl: `ws://127.0.0.1:${port}/ws`,
    lobby,
    async close() {
      for (const c of wss.clients) c.terminate();
      wss.close();
      await new Promise<void>((r) => server.close(() => r()));
    },
  };
}

export async function api(base: string, method: string, path: string, body?: unknown, token?: string) {
  const res = await fetch(base + path, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, body: (await res.json()) as any };
}

/** 受け取ったメッセージをためておき、条件に合うものを待てる WebSocket クライアント */
export class Client {
  ws: WebSocket;
  inbox: any[] = [];
  private waiters: Array<{ pred: (m: any) => boolean; resolve: (m: any) => void }> = [];

  constructor(url: string) {
    this.ws = new WebSocket(url);
    this.ws.on("message", (d) => {
      const m = JSON.parse(d.toString());
      this.inbox.push(m);
      for (const w of [...this.waiters]) {
        if (w.pred(m)) {
          this.waiters.splice(this.waiters.indexOf(w), 1);
          w.resolve(m);
        }
      }
      this.onMessage?.(m);
    });
  }

  onMessage: ((m: any) => void) | null = null;

  async open() {
    if (this.ws.readyState === WebSocket.OPEN) return;
    await new Promise((r) => this.ws.once("open", r));
  }

  send(m: unknown) {
    this.ws.send(JSON.stringify(m));
  }

  wait(pred: (m: any) => boolean, timeoutMs = 20000): Promise<any> {
    const found = this.inbox.find(pred);
    if (found) return Promise.resolve(found);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("timeout waiting; inbox=" + JSON.stringify(this.inbox.slice(-5)))), timeoutMs);
      this.waiters.push({ pred, resolve: (m) => { clearTimeout(timer); resolve(m); } });
    });
  }

  close() {
    this.ws.close();
  }
}

export async function guest(base: string, wsUrl: string, name: string, consent = true) {
  const g = await api(base, "POST", "/api/v1/guest", { name });
  // 対戦の同意（要件#101）。テストではふつう同意しておく
  if (consent) await api(base, "POST", "/api/v1/me/consent", { agree: true, version: 1 }, g.body.token);
  const c = new Client(wsUrl);
  await c.open();
  c.send({ t: "auth", token: g.body.token });
  await c.wait((m) => m.t === "hello");
  return { token: g.body.token as string, player: g.body.player, c };
}

/** 自分の番が来たら自動で返事をする（店員はよい返事、客は圧のあるセリフ） */
export function autoplay(c: Client, opts: { voice?: boolean; staffText?: string } = {}) {
  let n = 0;
  c.onMessage = (m) => {
    if (m.t === "phase" && m.turn === "you" && (m.phase === "staff_turn" || m.phase === "customer_turn")) {
      n++;
      const text = m.phase === "staff_turn"
        ? (opts.staffText ?? `申し訳ございません。お気持ちお察しいたします。すぐに確認いたします。（${n}）`)
        : `責任者を出せ！こっちは客だぞ！どうしてくれるんだ！（${n}）`;
      setTimeout(() => {
        if (opts.voice) {
          // 1秒ぶんの μ-law 音声（中身は小さな音）。mock の文字起こしは debug_text を返す
          const audio = Buffer.alloc(16000, 0xd5).toString("base64");
          c.send({ t: "voice", audio, debug_text: text });
        } else {
          c.send({ t: "say", text });
        }
      }, 20);
    }
  };
}
