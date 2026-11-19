// 管理画面（要件#100）: 外からつながらないこと・ログイン・CSRF・設定の変更・利用停止・メンテナンス・警告・お知らせ・会話の保存
import http from "node:http";
import { test, after, before } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
process.env.ADMIN_PASSWORD = "test-admin-password-123";
const { startServer, api, guest } = await import("./helpers.ts");
const { createAdminServer } = await import("../src/admin.ts");
const { config } = await import("../src/config.ts");
const { runtime } = await import("../src/settings.ts");

let srv: Awaited<ReturnType<typeof startServer>>;
let admin: http.Server;
let port = 0;
before(async () => {
  srv = await startServer();
  admin = createAdminServer(srv.lobby);
  await new Promise<void>((r) => admin.listen(0, "127.0.0.1", () => r()));
  port = (admin.address() as AddressInfo).port;
});
after(async () => {
  admin.close();
  await srv.close();
});

/** 管理画面に送る（Host・Cookie・CSRF を指定できる） */
function req(method: string, path: string, opts: { body?: unknown; cookie?: string; csrf?: string; headers?: Record<string, string> } = {}): Promise<{ status: number; body: any; setCookie: string }> {
  return new Promise((resolve, reject) => {
    const data = opts.body === undefined ? undefined : JSON.stringify(opts.body);
    const r = http.request({ host: "127.0.0.1", port, method, path, headers: {
      host: `127.0.0.1:${port}`, "content-type": "application/json",
      ...(opts.cookie ? { cookie: opts.cookie } : {}), ...(opts.csrf ? { "x-admin-csrf": opts.csrf } : {}), ...(opts.headers ?? {}),
    } }, (res) => {
      let b = "";
      res.on("data", (c) => (b += c));
      res.on("end", () => {
        let j: any = b;
        try { j = JSON.parse(b); } catch { /* html */ }
        resolve({ status: res.statusCode ?? 0, body: j, setCookie: String(res.headers["set-cookie"] ?? "") });
      });
    });
    r.on("error", reject);
    if (data) r.write(data);
    r.end();
  });
}

async function login(): Promise<{ cookie: string; csrf: string }> {
  const r = await req("POST", "/api/login", { body: { password: "test-admin-password-123" } });
  assert.equal(r.status, 200);
  return { cookie: r.setCookie.split(";")[0], csrf: r.body.csrf };
}

test("管理画面: プロキシを通った接続・ちがう Host は断る。ゲームのポートからは管理の API が見えない", async () => {
  assert.equal((await req("GET", "/", { headers: { "x-forwarded-for": "1.2.3.4" } })).status, 403);
  assert.equal((await req("GET", "/", { headers: { "cf-connecting-ip": "1.2.3.4" } })).status, 403);
  assert.equal((await req("GET", "/", { headers: { host: "evil.example.com" } })).status, 403);
  const page = await req("GET", "/");
  assert.equal(page.status, 200);
  assert.match(String(page.body), /管理画面/);
  assert.equal((await req("GET", "/api/status")).status, 401, "ログインしないと見られない");
  const game = await fetch(srv.base + "/api/status");
  assert.notEqual(game.status, 200, "ゲームのポートには管理の API がない");
  const gp = await fetch(srv.base + "/");
  assert.ok(!(await gp.text()).includes("管理画面"), "ゲームのポートに管理画面は出ない");
});

test("管理画面: パスワードがちがえば入れず、変更の操作には CSRF の印が要る", async () => {
  assert.equal((await req("POST", "/api/login", { body: { password: "wrong" } })).status, 401);
  const { cookie, csrf } = await login();
  assert.equal((await req("GET", "/api/status", { cookie })).status, 200);
  const no = await req("POST", "/api/settings", { cookie, body: { key: "versus.openingSec", value: 50 } });
  assert.equal(no.status, 403, "CSRF の印がないと変えられない");
  const bad = await req("POST", "/api/settings", { cookie, csrf, headers: { origin: "http://evil.example.com" }, body: { key: "versus.openingSec", value: 50 } });
  assert.equal(bad.status, 403, "ほかのサイトからは変えられない");
});

test("管理画面: 設定を変えるとすぐ効き、範囲外は断り、記録から戻せる。APIキーは隠して見せる", async () => {
  const { cookie, csrf } = await login();
  const before = config.versus.openingSec;
  const ok = await req("POST", "/api/settings", { cookie, csrf, body: { key: "versus.openingSec", value: 60 } });
  assert.equal(ok.status, 200);
  assert.equal(config.versus.openingSec, 60);
  const info = await api(srv.base, "GET", "/api/v1/info");
  assert.equal(info.body.rules.opening_seconds, 60, "ゲームにもすぐ伝わる");
  assert.equal((await req("POST", "/api/settings", { cookie, csrf, body: { key: "versus.openingSec", value: 9999 } })).status, 400);
  assert.equal((await req("POST", "/api/settings", { cookie, csrf, body: { key: "llmMode", value: "nonsense" } })).status, 400);
  const audit = await req("GET", "/api/audit", { cookie });
  const entry = audit.body.logs.find((x: any) => x.action === "setting" && x.target === "versus.openingSec");
  assert.ok(entry);
  assert.equal((await req("POST", "/api/revert", { cookie, csrf, body: { log_id: entry.id } })).status, 200);
  assert.equal(config.versus.openingSec, before, "前の値に戻った");
  // APIキー
  const key = "sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  assert.equal((await req("POST", "/api/settings", { cookie, csrf, body: { key: "ANTHROPIC_API_KEY", value: key } })).status, 200);
  assert.equal(process.env.ANTHROPIC_API_KEY, key);
  const list = await req("GET", "/api/settings", { cookie });
  const shown = list.body.settings.find((x: any) => x.key === "ANTHROPIC_API_KEY");
  assert.ok(!JSON.stringify(list.body).includes(key), "キーは全部は見せない");
  assert.equal(shown.is_set, true);
  assert.equal((await req("POST", "/api/settings", { cookie, csrf, body: { key: "ANTHROPIC_API_KEY", value: "" } })).status, 200);
  assert.equal(process.env.ANTHROPIC_API_KEY, undefined);
  const a2 = await req("GET", "/api/audit", { cookie });
  assert.ok(!JSON.stringify(a2.body).includes(key), "記録にもキーは残らない");
});

test("管理画面: 利用停止・対戦だけの停止・警告・メンテナンス・お知らせがゲームに効く", async () => {
  const { cookie, csrf } = await login();
  const g = await guest(srv.base, srv.wsUrl, "わるいひと");
  const id = g.player.id;
  // 警告
  assert.equal((await req("POST", `/api/players/${id}/action`, { cookie, csrf, body: { type: "warn", message: "暴言はやめてください" } })).status, 200);
  const me = await api(srv.base, "GET", "/api/v1/me", undefined, g.token);
  assert.equal(me.body.warning, "暴言はやめてください");
  await api(srv.base, "POST", "/api/v1/me/ack_warning", {}, g.token);
  assert.equal((await api(srv.base, "GET", "/api/v1/me", undefined, g.token)).body.warning, "");
  // 対戦だけ止める
  await req("POST", `/api/players/${id}/action`, { cookie, csrf, body: { type: "suspend", scope: "versus", hours: 24, reason: "暴言" } });
  g.c.send({ t: "queue", format: "text" });
  const err = await g.c.wait((m) => m.t === "error");
  assert.equal(err.code, "versus_banned");
  // 全部止める → ログインできず、つながっていた接続も切れる
  await req("POST", `/api/players/${id}/action`, { cookie, csrf, body: { type: "ban", reason: "くり返しの暴言" } });
  const me2 = await api(srv.base, "GET", "/api/v1/me", undefined, g.token);
  assert.equal(me2.status, 403);
  assert.equal(me2.body.error.code, "banned");
  await req("POST", `/api/players/${id}/action`, { cookie, csrf, body: { type: "unban" } });
  assert.equal((await api(srv.base, "GET", "/api/v1/me", undefined, g.token)).status, 200);
  // 名前のリセット
  await req("POST", `/api/players/${id}/action`, { cookie, csrf, body: { type: "reset_name" } });
  assert.equal((await api(srv.base, "GET", "/api/v1/me", undefined, g.token)).body.player.name, "名無しのスタッフ");
  // メンテナンス
  await req("POST", "/api/settings", { cookie, csrf, body: { key: "maintenanceMessage", value: "22時まで点検中" } });
  await req("POST", "/api/settings", { cookie, csrf, body: { key: "maintenance", value: true } });
  const info = await api(srv.base, "GET", "/api/v1/info");
  assert.equal(info.body.maintenance, true);
  assert.equal(info.body.maintenance_message, "22時まで点検中");
  const g2 = await guest(srv.base, srv.wsUrl, "ふつうのひと");
  g2.c.send({ t: "queue", format: "text" });
  assert.equal((await g2.c.wait((m) => m.t === "error")).code, "maintenance");
  await req("POST", "/api/settings", { cookie, csrf, body: { key: "maintenance", value: false } });
  assert.equal(runtime.maintenance, false);
  // お知らせ
  // 画像: PNG・JPEG だけ。だれでも読める URL で配る
  const png = Buffer.from("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da63f8cf00000301010018dd8db00000000049454e44ae426082", "hex");
  const bad = await req("POST", "/api/announcements/image", { cookie, csrf, body: { data: Buffer.from("<script>alert(1)</script>").toString("base64") } });
  assert.equal(bad.status, 400, "画像でないものは断る");
  const up = await req("POST", "/api/announcements/image", { cookie, csrf, body: { data: png.toString("base64") } });
  assert.equal(up.status, 200);
  assert.match(up.body.name, /^[0-9a-f]{32}\.png$/);
  await req("POST", "/api/announcements", { cookie, csrf, body: { title_ja: "新しい背景が出ました", title_en: "New backdrops are out", text_ja: "**10種類**の背景を追加しました", font: "hand", image: up.body.name } });
  const info2 = await api(srv.base, "GET", "/api/v1/info");
  const n = info2.body.notices[0];
  assert.equal(n.title.ja, "新しい背景が出ました");
  assert.equal(n.title.zh, "New backdrops are out", "中国語が空なら英語");
  assert.equal(n.body.en, "**10種類**の背景を追加しました", "英語の本文が空なら日本語");
  assert.equal(n.font, "hand");
  const imgRes = await fetch(srv.base + n.image);
  assert.equal(imgRes.status, 200);
  assert.equal(imgRes.headers.get("content-type"), "image/png");
  assert.equal((await fetch(srv.base + "/api/v1/notice_image/../../etc/passwd")).status !== 200, true, "画像のほかのファイルは読めない");
  // 直す・下げる
  const list = await req("GET", "/api/announcements", { cookie });
  const nid = list.body.announcements[0].id;
  await req("POST", `/api/announcements/${nid}`, { cookie, csrf, body: { title_ja: "直した見出し", text_ja: "本文", font: "sign", image: "" } });
  assert.equal((await api(srv.base, "GET", "/api/v1/info")).body.notices[0].title.ja, "直した見出し");
  await req("POST", `/api/announcements/${nid}`, { cookie, csrf, body: { active: false } });
  assert.ok(!(await api(srv.base, "GET", "/api/v1/info")).body.notices.some((x: any) => x.id === nid), "下げたら出ない");
  g2.c.close();
  try { g.c.close(); } catch { /* 切れている */ }
});

test("通報された試合だけ会話を保存し、30日を過ぎたら消す", async () => {
  const { trackMatch, endMatch, markReported } = await import("../src/matchlogs.ts");
  const { matchLog, purgeMatchLogs } = await import("../src/db.ts");
  const a = "00000000-0000-4000-8000-000000000001";
  const b = "00000000-0000-4000-8000-000000000002";
  trackMatch(a, { lines: [{ text: "こんにちは" }] });
  endMatch(a);
  assert.equal(matchLog(a), null, "通報がなければ保存しない");
  trackMatch(b, { lines: [{ text: "ひどいこと" }] });
  markReported(b);
  assert.equal(matchLog(b), null, "試合中は、まだ保存しない");
  endMatch(b);
  assert.deepEqual(matchLog(b), { lines: [{ text: "ひどいこと" }] });
  markReported(a);
  assert.ok(matchLog(a), "終わってから1時間以内の通報なら保存する");
  assert.equal(purgeMatchLogs(Date.now() + 31 * 86_400_000), 2);
  assert.equal(matchLog(b), null);
});

test("AIの使用量を日ごとに数え、料金の目安を出す", async () => {
  const { addAiUsage } = await import("../src/db.ts");
  const { cookie } = await login();
  addAiUsage("claude-haiku-5-5", { input: 1_000_000, output: 200_000, cacheRead: 0, cacheWrite: 0 });
  const u = await req("GET", "/api/usage", { cookie });
  const row = u.body.rows.find((x: any) => x.model === "claude-haiku-5-5");
  assert.ok(row);
  assert.ok(Math.abs(row.cost_usd - (0.1 + 0.2 * 0.5)) < 0.0001, `目安 ${row.cost_usd}`);
});
