// Claude を呼ぶときの料金対策（要件#93）を、偽の API サーバーで確かめる。
// - 会話の最後の行にキャッシュの印がつき、前回の呼び出しと前の部分がそろう
// - 不適切な発言の判定（flag）が採点と同じ1回の呼び出しで返る
import http from "node:http";
import { test } from "node:test";
import assert from "node:assert/strict";

type Block = { type: string; text: string; cache_control?: unknown };

test("会話をキャッシュでき、不適切な発言の判定が採点と一緒に返る", async () => {
  const seen: Array<{ system: Block[]; messages: Array<{ content: Block[] }> }> = [];
  const srv = http.createServer((req, res) => {
    let b = "";
    req.on("data", (c) => (b += c));
    req.on("end", () => {
      seen.push(JSON.parse(b));
      res.setHeader("content-type", "application/json");
      res.end(JSON.stringify({
        id: "msg_test", type: "message", role: "assistant", model: "claude-haiku-5-5", stop_reason: "end_turn", stop_sequence: null,
        content: [{ type: "text", text: JSON.stringify({ anger_delta: 5, resolve_delta: 0, yielded: false, customer_reply: "なんだと", comment: "落ち着こう", flag: "sexual" }) }],
        usage: { input_tokens: 50, output_tokens: 20, cache_read_input_tokens: 900, cache_creation_input_tokens: 30 },
      }));
    });
  });
  await new Promise<void>((r) => srv.listen(0, r));
  const port = (srv.address() as { port: number }).port;
  process.env.LLM_MODE = "claude";
  process.env.ANTHROPIC_API_KEY = "test-key";
  process.env.ANTHROPIC_BASE_URL = `http://127.0.0.1:${port}`;
  const llm = await import("../src/llm.ts");
  const { allCustomers } = await import("../src/scenarios.ts");
  const c = allCustomers("konbini")[0];
  const history = [{ role: "customer" as const, text: c.opening }, { role: "staff" as const, text: "申し訳ございません" }];
  const r1 = await llm.judgeStaffTurn("konbini", c, history, 40, 0, false, "ja");
  assert.equal(r1.flag, "sexual");
  history.push({ role: "customer", text: "謝って済むか" }, { role: "staff", text: "交換いたします" });
  await llm.judgeStaffTurn("konbini", c, history, 45, 10, false, "ja");
  assert.equal(seen.length, 2);
  // 指示文はキャッシュする
  assert.ok(seen[0].system[0].cache_control);
  const a = seen[0].messages[0].content;
  const b = seen[1].messages[0].content;
  // 印は会話の最後の行だけ（変わる部分＝怒りの数値は印の後ろ）
  const marked = (blocks: Block[]) => blocks.map((x, i) => (x.cache_control ? i : -1)).filter((i) => i >= 0);
  assert.deepEqual(marked(a), [a.length - 2]);
  assert.deepEqual(marked(b), [b.length - 2]);
  assert.match(a[a.length - 1].text, /怒り: 40/);
  // 1回目の印のところまでが、2回目の前の部分とまったく同じ（＝キャッシュから読める）
  for (let i = 0; i <= a.length - 2; i++) assert.equal(b[i].text, a[i].text);
  assert.equal(llm.cacheStats.cacheRead, 1800);
  srv.close();
});
