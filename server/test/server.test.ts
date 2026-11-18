import fs from "node:fs";
import { test, after, before } from "node:test";
import assert from "node:assert/strict";
import { startServer, api, guest, autoplay, Client } from "./helpers.ts";

let srv: Awaited<ReturnType<typeof startServer>>;
before(async () => { srv = await startServer(); });
after(async () => { await srv.close(); });

test("info と ゲスト作成と /me", async () => {
  const info = await api(srv.base, "GET", "/api/v1/info");
  assert.equal(info.status, 200);
  assert.equal(info.body.ai, false);
  assert.equal(info.body.voice, true);
  const g = await api(srv.base, "POST", "/api/v1/guest", { name: "  テスト<店員>  " });
  assert.equal(g.status, 200);
  assert.equal(g.body.player.name, "テスト店員");
  assert.equal(g.body.player.rating, 1000);
  const me = await api(srv.base, "GET", "/api/v1/me", undefined, g.body.token);
  assert.equal(me.body.player.id, g.body.player.id);
  const bad = await api(srv.base, "GET", "/api/v1/me", undefined, "nope");
  assert.equal(bad.status, 401);
  assert.match(bad.body.error.message, /ログイン/);
});

test("1人用: お客さん → 返事の判定", async () => {
  const g = await api(srv.base, "POST", "/api/v1/guest", { name: "ソロ" });
  const t = g.body.token;
  const start = await api(srv.base, "POST", "/api/v1/solo/start", { stage: "arcade", avoid: [] }, t);
  assert.equal(start.status, 200);
  assert.equal(start.body.source, "script");
  assert.ok(start.body.customer.opening.length > 0);
  assert.equal(start.body.customer.solution_keywords, undefined, "採点用キーワードはクライアントに渡さない");
  const turn = await api(srv.base, "POST", "/api/v1/solo/turn", { session_id: start.body.session_id, reply: "うるさい、帰れ", anger: 40, resolve: 0 }, t);
  assert.equal(turn.status, 200);
  assert.ok(turn.body.anger_delta >= 20, "暴言で怒りが大きく上がる");
  assert.equal(turn.body.judged_by, "keyword");
  const other = await api(srv.base, "POST", "/api/v1/guest", { name: "他人" });
  const stolen = await api(srv.base, "POST", "/api/v1/solo/turn", { session_id: start.body.session_id, reply: "x", anger: 0, resolve: 0 }, other.body.token);
  assert.equal(stolen.status, 404, "他人のセッションは使えない");
  const badStage = await api(srv.base, "POST", "/api/v1/solo/start", { stage: "moon" }, t);
  assert.equal(badStage.status, 400);
});

test("ランクマッチ（文字）: 2ラウンド戦ってレーティングが動く", async () => {
  const a = await guest(srv.base, srv.wsUrl, "Aさん");
  const b = await guest(srv.base, srv.wsUrl, "Bさん");
  autoplay(a.c);
  autoplay(b.c, { staffText: "うるさい" });
  a.c.send({ t: "queue", format: "text" });
  b.c.send({ t: "queue", format: "text" });
  const fa = await a.c.wait((m) => m.t === "match_found");
  assert.equal(fa.kind, "ranked");
  assert.equal(fa.opponent.name, "Bさん");
  const ea = await a.c.wait((m) => m.t === "match_end", 60000);
  const eb = await b.c.wait((m) => m.t === "match_end", 60000);
  assert.equal(ea.reason, "completed");
  assert.equal(ea.result, "win", "よい返事をしたAが勝つ");
  assert.equal(eb.result, "lose");
  assert.ok(ea.rating_delta > 0 && eb.rating_delta < 0);
  assert.equal(ea.rating_after, 1000 + ea.rating_delta);
  const me = await api(srv.base, "GET", "/api/v1/me", undefined, a.token);
  assert.equal(me.body.player.rating, ea.rating_after, "レーティングはサーバーに保存される");
  assert.equal(me.body.player.wins, 1);
  // 判定と台詞のやりとりが両者に届いている
  assert.ok(a.c.inbox.some((m) => m.t === "judged"));
  assert.ok(b.c.inbox.some((m) => m.t === "line" && m.by === "opponent"));
  const board = await api(srv.base, "GET", "/api/v1/leaderboard");
  assert.equal(board.body.players[0].name, "Aさん");
  a.c.close(); b.c.close();
});

test("フレンド対戦（部屋コード）: レーティングは変わらない", async () => {
  const a = await guest(srv.base, srv.wsUrl, "ホスト");
  const b = await guest(srv.base, srv.wsUrl, "フレンド");
  autoplay(a.c); autoplay(b.c);
  a.c.send({ t: "room_create", format: "text" });
  const room = await a.c.wait((m) => m.t === "room_created");
  assert.match(room.code, /^[A-Z2-9]{6}$/);
  b.c.send({ t: "room_join", code: "zzzzzz" });
  const err = await b.c.wait((m) => m.t === "error");
  assert.equal(err.code, "room_not_found");
  b.c.send({ t: "room_join", code: room.code.toLowerCase() });
  const f = await b.c.wait((m) => m.t === "match_found");
  assert.equal(f.kind, "friend");
  const e = await a.c.wait((m) => m.t === "match_end", 60000);
  assert.equal(e.rating_delta, 0);
  assert.equal(e.rating_after, 1000);
  a.c.close(); b.c.close();
});

test("音声対戦: 声が相手に届き、文字起こしされて判定される", async () => {
  const a = await guest(srv.base, srv.wsUrl, "声A");
  const b = await guest(srv.base, srv.wsUrl, "声B");
  autoplay(a.c, { voice: true }); autoplay(b.c, { voice: true });
  a.c.send({ t: "room_create", format: "voice" });
  const room = await a.c.wait((m) => m.t === "room_created");
  b.c.send({ t: "room_join", code: room.code });
  await a.c.wait((m) => m.t === "match_end", 60000);
  assert.ok(b.c.inbox.some((m) => m.t === "voice" && m.by === "opponent" && typeof m.audio === "string"), "相手の声が届く");
  assert.ok(a.c.inbox.some((m) => m.t === "line" && m.via === "voice"), "文字起こしがセリフになる");
  a.c.close(); b.c.close();
});

test("途中で抜けると相手の勝ち（ランク）", async () => {
  const a = await guest(srv.base, srv.wsUrl, "残る人");
  const b = await guest(srv.base, srv.wsUrl, "抜ける人");
  a.c.send({ t: "queue", format: "text" });
  b.c.send({ t: "queue", format: "text" });
  await b.c.wait((m) => m.t === "match_found");
  b.c.send({ t: "leave" });
  const e = await a.c.wait((m) => m.t === "match_end");
  assert.equal(e.result, "win");
  assert.equal(e.reason, "left");
  a.c.close(); b.c.close();
});

test("切断しても猶予時間内につなぎ直せば試合に戻れる", async () => {
  const a = await guest(srv.base, srv.wsUrl, "再接続A");
  const b = await guest(srv.base, srv.wsUrl, "再接続B");
  a.c.send({ t: "room_create", format: "text" });
  const room = await a.c.wait((m) => m.t === "room_created");
  b.c.send({ t: "room_join", code: room.code });
  await b.c.wait((m) => m.t === "match_found");
  b.c.ws.terminate();
  await a.c.wait((m) => m.t === "opponent_status" && m.connected === false);
  const c2 = new Client(srv.wsUrl);
  await c2.open();
  c2.send({ t: "auth", token: b.token });
  const hello = await c2.wait((m) => m.t === "hello");
  assert.equal(hello.resumed, true);
  await c2.wait((m) => m.t === "match_found");
  await a.c.wait((m) => m.t === "opponent_status" && m.connected === true);
  c2.send({ t: "leave" });
  await a.c.wait((m) => m.t === "match_end");
  a.c.close(); c2.close();
});

test("ランクマッチは同じ言語どうしで組む", async () => {
  const a = await guest(srv.base, srv.wsUrl, "日本語の人");
  const b = await guest(srv.base, srv.wsUrl, "English player");
  b.c.send({ t: "lang", lang: "en" });
  a.c.send({ t: "queue", format: "text" });
  b.c.send({ t: "queue", format: "text" });
  const qb = await b.c.wait((m) => m.t === "queued");
  assert.equal(qb.lang, "en");
  await new Promise((r) => setTimeout(r, 300));
  assert.ok(!a.c.inbox.some((m) => m.t === "match_found"), "言語が違うと組まれない");
  const c = await guest(srv.base, srv.wsUrl, "Another");
  c.c.send({ t: "lang", lang: "en" });
  c.c.send({ t: "queue", format: "text" });
  const f = await b.c.wait((m) => m.t === "match_found");
  assert.equal(f.lang, "en");
  assert.equal(f.opponent.name, "Another");
  b.c.send({ t: "leave" });
  await c.c.wait((m) => m.t === "match_end");
  a.c.send({ t: "cancel" });
  a.c.close(); b.c.close(); c.c.close();
});

test("1人用の行動ボタンと、対戦の行動・フレンド部屋の返事の時間", async () => {
  const g = await api(srv.base, "POST", "/api/v1/guest", { name: "行動" });
  const start = await api(srv.base, "POST", "/api/v1/solo/start", { stage: "konbini" }, g.body.token);
  // 先に使えない行動を試す（土下座でお客さんによっては会話が終わり、その後は 409 になるため）
  const bad = await api(srv.base, "POST", "/api/v1/solo/turn", { session_id: start.body.session_id, action: "medal_return", anger: 40, resolve: 0 }, g.body.token);
  assert.equal(bad.status, 400, "コンビニでメダルは返せない");
  const act = await api(srv.base, "POST", "/api/v1/solo/turn", { session_id: start.body.session_id, action: "dogeza", anger: 40, resolve: 0 }, g.body.token);
  assert.equal(act.status, 200);
  assert.equal(act.body.action, "dogeza");

  const a = await guest(srv.base, srv.wsUrl, "部屋主");
  const b = await guest(srv.base, srv.wsUrl, "客");
  a.c.send({ t: "room_create", format: "text", answer_time: "slow" });
  const room = await a.c.wait((m) => m.t === "room_created");
  b.c.send({ t: "room_join", code: room.code });
  const rs = await a.c.wait((m) => m.t === "round_start");
  assert.ok(rs.rate < 1.1 * 1.4 * 0.61 + 0.01, `ゆっくりなら怒りの速さが下がる: ${rs.rate}`);
  // 店員役が行動ボタンを押す
  const staffClient = rs.role === "staff" ? a.c : b.c;
  const custClient = rs.role === "staff" ? b.c : a.c;
  await custClient.wait((m) => m.t === "phase" && m.phase === "customer_turn" && m.turn === "you");
  custClient.send({ t: "say", text: "責任者を出せ！" });
  await staffClient.wait((m) => m.t === "phase" && m.phase === "staff_turn" && m.turn === "you");
  const found = await a.c.wait((m) => m.t === "match_found");
  // ゲームセンターは台の種類でボタンが変わる（要件#54）。ミニゲームのボタン（結果で送る）は除く
  const table = JSON.parse(fs.readFileSync(new URL("../../data/actions.json", import.meta.url), "utf-8"));
  const ids: string[] = found.stage === "konbini" ? table.stages.konbini : table.machines[rs.card.machine ?? "none"];
  const id = ids.find((x) => !table.minigame.includes(x))!;
  staffClient.send({ t: "act", id: "medal_return_x" }); // 存在しない行動は無視される
  staffClient.send({ t: "act", id });
  const line = await custClient.wait((m) => m.t === "line" && m.via === "action");
  assert.ok(line.text.includes(table.labels.ja[id]), `${line.text} に ${table.labels.ja[id]}`);
  a.c.send({ t: "leave" });
  await b.c.wait((m) => m.t === "match_end");
  a.c.close(); b.c.close();
});

test("同じ人は二重に並べない／音声の形式チェック", async () => {
  const a = await guest(srv.base, srv.wsUrl, "二重");
  a.c.send({ t: "queue", format: "text" });
  await a.c.wait((m) => m.t === "queued");
  a.c.send({ t: "room_create", format: "text" });
  const err = await a.c.wait((m) => m.t === "error");
  assert.equal(err.code, "busy");
  a.c.send({ t: "cancel" });
  await a.c.wait((m) => m.t === "cancelled");
  a.c.send({ t: "queue", format: "video" });
  const err2 = await a.c.wait((m) => m.t === "error" && m.code === "bad_format");
  assert.ok(err2);
  a.c.close();
});

test("EOS で組んだランクの部屋（要件#32, #48）: 同じ回線は不可、別の回線ならランクマッチになる", async () => {
  const { config } = await import("../src/config.ts");
  const a = await guest(srv.base, srv.wsUrl, "EOSホスト");
  const b = await guest(srv.base, srv.wsUrl, "EOS参加");
  config.allowSameIpRanked = false;
  a.c.send({ t: "room_create", format: "text", ranked: true, eos_lobby: "abc" });
  const room = await a.c.wait((m) => m.t === "room_created");
  b.c.send({ t: "room_join", code: room.code });
  const err = await b.c.wait((m) => m.t === "error");
  assert.equal(err.code, "same_network");
  config.allowSameIpRanked = true;
  b.c.send({ t: "room_join", code: room.code });
  const f = await b.c.wait((m) => m.t === "match_found");
  assert.equal(f.kind, "ranked");
  b.c.send({ t: "leave" });
  await a.c.wait((m) => m.t === "match_end");
  config.allowRankedRooms = false;
  a.c.send({ t: "room_create", format: "text", ranked: true, eos_lobby: "abc" });
  const err2 = await a.c.wait((m) => m.t === "error" && m.code === "ranked_rooms_disabled");
  assert.ok(err2);
  config.allowRankedRooms = true;
  a.c.close(); b.c.close();
});

test("チート対策（要件#47）: 同じ回線どうしは組まない／誰も発言せずに抜けたら勝者は上がらない／同じ相手との連戦", async () => {
  const { config } = await import("../src/config.ts");
  // 1. 同じIP（テストはすべて 127.0.0.1）どうしはランクマッチで組まれない
  config.allowSameIpRanked = false;
  const a = await guest(srv.base, srv.wsUrl, "同IP-A");
  const b = await guest(srv.base, srv.wsUrl, "同IP-B");
  a.c.send({ t: "queue", format: "text" });
  b.c.send({ t: "queue", format: "text" });
  await new Promise((r) => setTimeout(r, 400));
  assert.ok(!a.c.inbox.some((m) => m.t === "match_found"), "同じ回線どうしは組まれない");
  a.c.send({ t: "cancel" });
  b.c.send({ t: "cancel" });
  config.allowSameIpRanked = true;

  // 2. 誰も発言しないうちに抜けた → 勝った側は上がらない、抜けた側は下がる
  a.c.send({ t: "queue", format: "text" });
  b.c.send({ t: "queue", format: "text" });
  await b.c.wait((m) => m.t === "match_found");
  b.c.send({ t: "leave" });
  const ea = await a.c.wait((m) => m.t === "match_end");
  const eb = await b.c.wait((m) => m.t === "match_end");
  assert.equal(ea.rating_delta, 0);
  assert.equal(ea.rating_note, "early_leave");
  assert.ok(eb.rating_delta < 0);

  // 3. 同じ相手と24時間で上限回数を超えたら動かない
  const before = config.samePairLimit24h;
  config.samePairLimit24h = 1;
  a.c.inbox.length = 0;
  b.c.inbox.length = 0;
  a.c.send({ t: "queue", format: "text" });
  b.c.send({ t: "queue", format: "text" });
  await b.c.wait((m) => m.t === "match_found");
  b.c.send({ t: "leave" });
  const eb2 = await b.c.wait((m) => m.t === "match_end");
  assert.equal(eb2.rating_delta, 0);
  assert.equal(eb2.rating_note, "same_pair");
  config.samePairLimit24h = before;
  a.c.close(); b.c.close();
});

test("チート対策: 1人用は納得をサーバーの値で検証し、決着後は受け付けない", async () => {
  const g = await api(srv.base, "POST", "/api/v1/guest", { name: "ソロ検証" });
  const t = g.body.token;
  const start = await api(srv.base, "POST", "/api/v1/solo/start", { stage: "konbini" }, t);
  const sid = start.body.session_id;
  // 納得を 99 と偽っても、サーバーは自分の値（0）を使う
  const r1 = await api(srv.base, "POST", "/api/v1/solo/turn", { session_id: sid, reply: "うるさい", anger: 0, resolve: 99 }, t);
  assert.equal(r1.body.resolve, 0);
  assert.ok(r1.body.anger >= start.body.customer.start_anger, "怒りは下げられない");
  // 屈服させて決着させる
  const lecturer = start.body.customer;
  const r2 = await api(srv.base, "POST", "/api/v1/solo/turn", { session_id: sid, action: "dogeza", anger: 0, resolve: 0 }, t);
  if (r2.body.yielded) {
    const r3 = await api(srv.base, "POST", "/api/v1/solo/turn", { session_id: sid, reply: "申し訳ございません", anger: 0, resolve: 0 }, t);
    assert.equal(r3.status, 409, "決着後は受け付けない");
  }
  assert.ok(lecturer.title);
});

test("要注意人物のイベントと店長のアドバイス（要件#52）", async () => {
  const g = await api(srv.base, "POST", "/api/v1/guest", { name: "店長" });
  const wild = await api(srv.base, "POST", "/api/v1/solo/start", { stage: "konbini", event: "wild" }, g.body.token);
  assert.equal(wild.status, 200);
  assert.equal(wild.body.event, "wild");
  assert.equal(wild.body.customer.rare, true, "要注意人物はネタ枠から選ぶ");
  const hint = await api(srv.base, "POST", "/api/v1/solo/hint", { session_id: wild.body.session_id }, g.body.token);
  assert.equal(hint.status, 200);
  assert.equal(typeof hint.body.keyword, "string");
  assert.ok(hint.body.keyword.length > 0, "解決の方向の言葉を1つ教える");
  const again = await api(srv.base, "POST", "/api/v1/solo/hint", { session_id: wild.body.session_id }, g.body.token);
  assert.equal(again.status, 409, "アドバイスは1人につき1回");
  const other = await api(srv.base, "POST", "/api/v1/guest", { name: "他人" });
  const steal = await api(srv.base, "POST", "/api/v1/solo/hint", { session_id: wild.body.session_id }, other.body.token);
  assert.equal(steal.status, 404, "他人の会話のアドバイスは聞けない");
});

test("セキュリティ（要件#77）: ログイン前は auth 以外を受け付けず切る", async () => {
  const { WebSocket } = await import("ws");
  const ws = new WebSocket(srv.wsUrl);
  await new Promise((r) => ws.once("open", r));
  const closed = new Promise<number>((r) => ws.once("close", (code) => r(code)));
  ws.send(JSON.stringify({ t: "queue", format: "text" }));
  assert.equal(await closed, 4001);
  const ws2 = new WebSocket(srv.wsUrl);
  await new Promise((r) => ws2.once("open", r));
  const closed2 = new Promise<number>((r) => ws2.once("close", (code) => r(code)));
  ws2.send(JSON.stringify({ t: "auth", token: "x".repeat(10000) }));
  assert.equal(await closed2, 4001, "ログイン前の大きなメッセージは切る");
});
