// Claude 以外の AI（OpenAI 互換の API）で判定できるか（要件#78）。偽の API サーバーを立てて確かめる
import http from "node:http";
import { test } from "node:test";
import assert from "node:assert/strict";

test("OpenAI 互換の API で判定できる（JSON の囲みを外す・スキーマで確かめる・キャッシュの数を数える）", async () => {
  let seen: Record<string, unknown> = {};
  const srv = http.createServer((req, res) => {
    let b = "";
    req.on("data", (c) => (b += c));
    req.on("end", () => {
      seen = JSON.parse(b);
      res.setHeader("content-type", "application/json");
      res.end(JSON.stringify({
        choices: [{ message: { content: '```json\n{"anger_delta":-5,"resolve_delta":20,"yielded":false,"customer_reply":"まあいい","comment":"よし"}\n```' }, finish_reason: "stop" }],
        usage: { prompt_tokens: 100, prompt_tokens_details: { cached_tokens: 80 } },
      }));
    });
  });
  await new Promise<void>((r) => srv.listen(0, r));
  const port = (srv.address() as { port: number }).port;
  process.env.LLM_PROVIDER = "openai_compatible";
  process.env.LLM_BASE_URL = `http://127.0.0.1:${port}/v1`;
  process.env.LLM_MODEL = "dummy-model";
  process.env.LLM_API_KEY = "test-key";
  const llm = await import("../src/llm.ts");
  const { allCustomers } = await import("../src/scenarios.ts");
  assert.equal(llm.llmEnabled(), true);
  const c = allCustomers("konbini")[0];
  const r = await llm.judgeStaffTurn("konbini", c, [{ role: "customer", text: c.opening }, { role: "staff", text: "申し訳ございません" }], 40, 0, false, "ja");
  assert.equal(r.resolve_delta, 20);
  assert.equal(seen.model, "dummy-model");
  assert.equal((seen.response_format as { type: string }).type, "json_schema");
  assert.equal(llm.cacheStats.cacheRead, 80);
  srv.close();
});
