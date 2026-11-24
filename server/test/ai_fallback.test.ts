// AI の API を優先順位の順に使い、失敗したら次へ切り替える（要件#115）。偽の API サーバーで確かめる
import http from "node:http";
import { test } from "node:test";
import assert from "node:assert/strict";

type Hits = { n: number; body?: Record<string, unknown> };
function fakeApi(status: number, hits: Hits) {
  const srv = http.createServer((req, res) => {
    let b = "";
    req.on("data", (c) => (b += c));
    req.on("end", () => {
      hits.n++;
      hits.body = JSON.parse(b);
      res.statusCode = status;
      res.setHeader("content-type", "application/json");
      res.end(status === 200
        ? JSON.stringify({ choices: [{ message: { content: '{"anger_delta":-3,"resolve_delta":15,"yielded":false,"customer_reply":"わかった","comment":"よし"}' }, finish_reason: "stop" }], usage: { prompt_tokens: 10, completion_tokens: 5 } })
        : JSON.stringify({ error: { message: "boom" } }));
    });
  });
  return new Promise<{ url: string; close: () => void }>((r) => srv.listen(0, () => r({ url: `http://127.0.0.1:${(srv.address() as { port: number }).port}/v1`, close: () => srv.close() })));
}

test("1位が失敗したら2位を使い、失敗した1位はしばらく飛ばす", async () => {
  const slots = await import("../src/ai_slots.ts");
  const llm = await import("../src/llm.ts");
  const { allCustomers } = await import("../src/scenarios.ts");
  const h1: Hits = { n: 0 }, h2: Hits = { n: 0 };
  const bad = await fakeApi(500, h1);
  const good = await fakeApi(200, h2);
  const x = { genModel: "", dailyLimit: 0, label: "" };
  slots.setStoredSlots({ versusSame: true, versus: [], solo: [
    { ...x, id: "aaaaaaa1", enabled: true, provider: "custom", model: "first", baseUrl: bad.url, jsonMode: "json_schema" },
    { ...x, id: "aaaaaaa2", enabled: false, provider: "custom", model: "off", baseUrl: good.url, jsonMode: "json_schema" },
    { ...x, id: "aaaaaaa3", enabled: true, provider: "custom", model: "third", baseUrl: good.url, jsonMode: "json_object" },
  ] });
  slots.resetSlotHealth();
  assert.equal(llm.llmEnabled(), true);
  const c = allCustomers("konbini")[0];
  const hist = [{ role: "customer" as const, text: c.opening }, { role: "staff" as const, text: "交換いたします" }];
  const r = await llm.judgeStaffTurn("konbini", c, hist, 40, 0, false, "ja");
  assert.equal(r.resolve_delta, 15, "3位（2位は休止）の答え");
  assert.equal(h1.n, 1);
  assert.equal(h2.n, 1);
  assert.equal(h2.body?.model, "third");
  assert.equal((h2.body?.response_format as { type: string }).type, "json_object", "json_object の API にはスキーマを指示文で伝える");
  assert.equal(slots.slotHealth("aaaaaaa1").fails, 1);
  assert.ok(slots.slotSkipped("aaaaaaa1"), "失敗した1位は飛ばす");
  // 2回目は1位を呼ばない
  await llm.judgeStaffTurn("konbini", c, hist, 40, 0, false, "ja");
  assert.equal(h1.n, 1);
  assert.equal(h2.n, 2);
  // 全部だめなら例外（呼び出し側はキーワード判定へ）
  slots.setStoredSlots({ versusSame: true, versus: [], solo: [{ ...x, id: "aaaaaaa1", enabled: true, provider: "custom", model: "first", baseUrl: bad.url, jsonMode: "json_schema" }] });
  await assert.rejects(() => llm.judgeStaffTurn("konbini", c, hist, 40, 0, false, "ja"), /休ませて/);
  // 対戦は別の並び。お客さんづくりだけ別のモデル、1日の上限（要件#116）
  slots.setStoredSlots({ versusSame: false, solo: [{ ...x, id: "aaaaaaa1", enabled: true, provider: "custom", model: "first", baseUrl: bad.url, jsonMode: "json_schema" }], versus: [
    { id: "aaaaaaa4", enabled: true, provider: "custom", model: "vs-judge", genModel: "vs-gen", dailyLimit: 1, label: "", baseUrl: good.url, jsonMode: "json_schema" },
    { ...x, id: "aaaaaaa5", enabled: true, provider: "custom", model: "vs-second", baseUrl: good.url, jsonMode: "json_schema" },
  ] });
  assert.equal(llm.llmEnabled("versus"), true);
  await llm.judgeStaffTurn("konbini", c, hist, 40, 0, false, "ja", "versus");
  assert.equal(h2.body?.model, "vs-judge", "対戦は対戦の並び");
  await llm.judgeStaffTurn("konbini", c, hist, 40, 0, false, "ja", "versus");
  assert.equal(h2.body?.model, "vs-second", "1日の上限（1回）に達したら次の順位へ");
  assert.equal(slots.slotHealth("aaaaaaa4").fails, 0, "上限は失敗に数えない");
  bad.close();
  good.close();
});

test("飛ばす時間: 連続10回目までは5分、そこから1回ごとに5分ずつ延ばして最大60分。成功したら0に戻る", async () => {
  const slots = await import("../src/ai_slots.ts");
  assert.equal(slots.skipMinutes(1), 5);
  assert.equal(slots.skipMinutes(10), 5);
  assert.equal(slots.skipMinutes(11), 10);
  assert.equal(slots.skipMinutes(12), 15);
  assert.equal(slots.skipMinutes(21), 60);
  assert.equal(slots.skipMinutes(50), 60);
  const t0 = 1_000_000;
  for (let i = 0; i < 11; i++) slots.slotFailed("bbbbbbb1", t0);
  assert.ok(slots.slotSkipped("bbbbbbb1", t0 + 9 * 60_000));
  assert.ok(!slots.slotSkipped("bbbbbbb1", t0 + 10 * 60_000 + 1));
  slots.slotSucceeded("bbbbbbb1");
  assert.equal(slots.slotHealth("bbbbbbb1").fails, 0);
});
